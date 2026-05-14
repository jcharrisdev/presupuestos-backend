import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

/// Simulador de decisiones financieras — cálculo 100% local, sin llamadas API.
///
/// El usuario ingresa un gasto hipotético y ve en tiempo real cómo afectaría
/// su disponible, su ritmo de gasto y su tasa de ahorro proyectada.
class SimuladorDecisionesScreen extends StatefulWidget {
  final double montoTotal;
  final double gastadoActual;
  final double ingresoNeto;    // 0 si no está configurado
  final double totalAhorro;
  final String nombrePresupuesto;

  const SimuladorDecisionesScreen({
    Key? key,
    required this.montoTotal,
    required this.gastadoActual,
    required this.ingresoNeto,
    required this.totalAhorro,
    required this.nombrePresupuesto,
  }) : super(key: key);

  @override
  State<SimuladorDecisionesScreen> createState() => _SimuladorDecisionesScreenState();
}

class _SimuladorDecisionesScreenState extends State<SimuladorDecisionesScreen> {
  final _montoCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  String _clasificacion = 'flexible';
  double _montoHip = 0;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _recalcular(String val) {
    setState(() { _montoHip = double.tryParse(val) ?? 0; });
  }

  @override
  Widget build(BuildContext context) {
    final disponibleActual = widget.montoTotal - widget.gastadoActual;
    final disponibleHip    = disponibleActual - _montoHip;
    final pctActual        = widget.montoTotal > 0 ? widget.gastadoActual / widget.montoTotal : 0.0;
    final pctHip           = widget.montoTotal > 0
        ? ((widget.gastadoActual + _montoHip) / widget.montoTotal).clamp(0.0, 1.5)
        : 0.0;
    final tasaAhorroActual = widget.ingresoNeto > 0
        ? (widget.totalAhorro / widget.ingresoNeto * 100).clamp(0.0, 100.0)
        : 0.0;
    final tasaAhorroHip    = widget.ingresoNeto > 0
        ? ((widget.totalAhorro - _montoHip) / widget.ingresoNeto * 100).clamp(0.0, 100.0)
        : 0.0;

    final excede    = disponibleHip < 0;
    final barColor  = pctHip >= 1.0 ? AppTheme.danger
        : pctHip >= 0.85 ? AppTheme.warning
        : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Simulador de decisiones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('¿Qué es el simulador?',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Ingresa el monto de un gasto hipotético y ve en tiempo real '
                  'cómo afectaría tu disponible, tu ritmo de gasto y tu tasa de ahorro.\n\n'
                  'No se guarda nada — es solo una proyección para ayudarte a decidir.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── HEADER ──────────────────────────────────────────────────────
          Text('Presupuesto: ${widget.nombrePresupuesto}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Disponible actual: \$${disponibleActual.toStringAsFixed(2)}',
            style: TextStyle(
              color: disponibleActual >= 0 ? AppTheme.success : AppTheme.danger,
              fontSize: 20, fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),

          // ── FORMULARIO ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('¿Qué quieres comprar?',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 14),
              TextField(
                controller: _descCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(hintText: 'Descripción (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
                onChanged: _recalcular,
              ),
              const SizedBox(height: 16),
              const Text('Clasificación',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                _clasifBtn('Esencial',   'esencial',   const Color(0xFF1890FF)),
                _clasifBtn('Importante', 'importante', AppTheme.primary),
                _clasifBtn('Flexible',   'flexible',   AppTheme.success),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          if (_montoHip > 0) ...[
            // ── RESULTADO ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: excede ? AppTheme.danger.withOpacity(0.08) : AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: excede ? AppTheme.danger.withOpacity(0.4) : AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(excede ? Icons.warning_rounded : Icons.check_circle_outline,
                      color: excede ? AppTheme.danger : AppTheme.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    excede ? 'Excederías el presupuesto' : 'Dentro del presupuesto',
                    style: TextStyle(
                      color: excede ? AppTheme.danger : AppTheme.success,
                      fontWeight: FontWeight.w700, fontSize: 15,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // Barra de gasto proyectado
                _ResultRow('Gasto actual', '\$${widget.gastadoActual.toStringAsFixed(2)}', AppTheme.textSecondary),
                _ResultRow('Gasto hipotético', '+\$${_montoHip.toStringAsFixed(2)}', AppTheme.warning),
                _ResultRow(
                  'Total proyectado',
                  '\$${(widget.gastadoActual + _montoHip).toStringAsFixed(2)} / \$${widget.montoTotal.toStringAsFixed(2)}',
                  excede ? AppTheme.danger : AppTheme.textPrimary,
                  bold: true,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pctHip.clamp(0.0, 1.0),
                    backgroundColor: AppTheme.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(barColor),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(pctHip * 100).toStringAsFixed(1)}% del presupuesto consumido',
                    style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.w600)),

                const Divider(color: AppTheme.border, height: 24),

                _ResultRow(
                  'Disponible después',
                  '\$${disponibleHip.toStringAsFixed(2)}',
                  excede ? AppTheme.danger : AppTheme.success,
                  bold: true,
                ),

                if (widget.ingresoNeto > 0) ...[
                  const Divider(color: AppTheme.border, height: 24),
                  _ResultRow('Tasa ahorro actual', '${tasaAhorroActual.toStringAsFixed(1)}%', AppTheme.textSecondary),
                  _ResultRow(
                    'Tasa ahorro proyectada',
                    '${tasaAhorroHip.toStringAsFixed(1)}%',
                    tasaAhorroHip >= 20 ? AppTheme.success : tasaAhorroHip >= 10 ? AppTheme.warning : AppTheme.danger,
                    bold: true,
                  ),
                ],
              ]),
            ),

            const SizedBox(height: 16),

            // Consejo contextual
            _Consejo(
              excede: excede,
              pctHip: pctHip,
              clasificacion: _clasificacion,
              tasaAhorro: tasaAhorroHip,
            ),
          ] else ...[
            Center(child: Column(children: [
              const SizedBox(height: 40),
              Icon(Icons.calculate_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text('Ingresa un monto para simular',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            ])),
          ],
        ]),
      ),
    );
  }

  Widget _clasifBtn(String label, String value, Color color) {
    final sel = _clasificacion == value;
    return GestureDetector(
      onTap: () => setState(() => _clasificacion = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.15) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? color : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? color : AppTheme.textSecondary,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _ResultRow(this.label, this.value, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
      Text(value, style: TextStyle(
        color: color, fontSize: 14,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      )),
    ]),
  );
}

class _Consejo extends StatelessWidget {
  final bool excede;
  final double pctHip;
  final String clasificacion;
  final double tasaAhorro;
  const _Consejo({required this.excede, required this.pctHip, required this.clasificacion, required this.tasaAhorro});

  @override
  Widget build(BuildContext context) {
    String texto;
    Color color;
    IconData icon;

    if (excede) {
      texto = 'Este gasto supera tu presupuesto. Considera reducirlo o esperar al próximo período.';
      color = AppTheme.danger; icon = Icons.block;
    } else if (pctHip >= 0.85) {
      texto = 'Llegarías al ${(pctHip * 100).toStringAsFixed(0)}% del presupuesto. Procede con cuidado.';
      color = AppTheme.warning; icon = Icons.warning_amber_rounded;
    } else if (clasificacion == 'flexible' && tasaAhorro < 10) {
      texto = 'Tu tasa de ahorro proyectada sería baja (${tasaAhorro.toStringAsFixed(1)}%). ¿Puedes posponerlo?';
      color = AppTheme.warning; icon = Icons.savings_outlined;
    } else {
      texto = 'Este gasto cabe bien en tu presupuesto. ¡Adelante!';
      color = AppTheme.success; icon = Icons.thumb_up_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(texto,
            style: TextStyle(color: color, fontSize: 13, height: 1.4))),
      ]),
    );
  }
}
