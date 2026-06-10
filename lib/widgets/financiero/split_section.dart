import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/api_client.dart';

enum TipoDivision { partesIguales, porPorcentaje }

class SplitParticipante {
  final email = TextEditingController();
  final porcentaje = TextEditingController();
  void dispose() {
    email.dispose();
    porcentaje.dispose();
  }
}

// Llama al backend para guardar splits y enviar emails.
// Retorna true si se envió correctamente (o si no había participantes válidos).
Future<bool> enviarSplitPuntual({
  required String firebaseUid,
  required String descripcion,
  required double montoTotal,
  required List<SplitParticipante> participantes,
  required TipoDivision tipo,
  int? registroGastoId,
}) async {
  final validos = participantes.where((p) => p.email.text.trim().isNotEmpty).toList();
  if (validos.isEmpty) return true;

  final int n = validos.length + 1; // +1 por el registrante
  final List<Map<String, dynamic>> items = validos.map((p) {
    final double monto;
    if (tipo == TipoDivision.partesIguales) {
      monto = montoTotal / n;
    } else {
      final pct = double.tryParse(p.porcentaje.text.trim()) ?? 0;
      monto = montoTotal * pct / 100;
    }
    return {'email': p.email.text.trim(), 'monto': double.parse(monto.toStringAsFixed(2))};
  }).toList();

  await ApiClient.post('/gastos/split-notificar', {
    'firebase_uid': firebaseUid,
    if (registroGastoId != null) 'registro_gasto_id': registroGastoId,
    'descripcion': descripcion,
    'monto_total': montoTotal,
    'remitente': firebaseUid,
    'participantes': items,
  });
  return true;
}

class SplitSection extends StatefulWidget {
  final double Function() getTotal;
  const SplitSection({super.key, required this.getTotal});

  @override
  State<SplitSection> createState() => SplitSectionState();
}

class SplitSectionState extends State<SplitSection> {
  bool activo = false;
  TipoDivision tipo = TipoDivision.partesIguales;
  final List<SplitParticipante> participantes = [SplitParticipante()];

  @override
  void dispose() {
    for (final p in participantes) {
      p.dispose();
    }
    super.dispose();
  }

  double get _total => widget.getTotal();
  int get _n => participantes.length + 1; // +1 = el registrante

  double _montoParticipante(SplitParticipante p) {
    if (tipo == TipoDivision.partesIguales) return _total / _n;
    final pct = double.tryParse(p.porcentaje.text.trim()) ?? 0;
    return _total * pct / 100;
  }

  double get _pctRestante {
    final usado = participantes.fold<double>(
        0, (s, p) => s + (double.tryParse(p.porcentaje.text.trim()) ?? 0));
    return (100 - usado).clamp(0, 100);
  }

  // X2 — validación de formato de email
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  bool _emailValido(String e) => _emailRe.hasMatch(e.trim());

  /// True si hay algún correo escrito con formato inválido (para que el caller
  /// pueda bloquear el envío si quiere).
  bool get hayEmailInvalido =>
      participantes.any((p) => p.email.text.trim().isNotEmpty && !_emailValido(p.email.text));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: activo ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Toggle
        Row(children: [
          Switch(
            value: activo,
            onChanged: (v) => setState(() => activo = v),
            activeColor: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('¿Lo compartiste con alguien?',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Notificamos por correo a cada persona',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
          ),
        ]),

        if (activo) ...[
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          // Tipo de división
          const Text('CÓMO DIVIDIRLO',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(children: [
            _TipoChip(
              label: 'Partes iguales',
              icono: Icons.people_outline,
              seleccionado: tipo == TipoDivision.partesIguales,
              onTap: () => setState(() => tipo = TipoDivision.partesIguales),
            ),
            const SizedBox(width: 8),
            _TipoChip(
              label: 'Por porcentaje',
              icono: Icons.percent_outlined,
              seleccionado: tipo == TipoDivision.porPorcentaje,
              onTap: () => setState(() => tipo = TipoDivision.porPorcentaje),
            ),
          ]),

          if (tipo == TipoDivision.partesIguales && _total > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '\$${ (_total / _n).toStringAsFixed(2) } por persona · $_n personas en total (incluido tú)',
                style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],

          if (tipo == TipoDivision.porPorcentaje) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Tu parte', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Text(
                  '${_pctRestante.toStringAsFixed(0)}%  ·  \$${(_total * _pctRestante / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: _pctRestante < 0 ? AppTheme.danger : AppTheme.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 12),

          // Participantes
          const Text('PARTICIPANTES',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 8),

          ...participantes.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: tipo == TipoDivision.porPorcentaje ? 5 : 8,
                  child: TextField(
                    controller: p.email,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Correo',
                      hintText: 'correo@ejemplo.com',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      // X2 — ícono de validez del email en tiempo real
                      errorText: (p.email.text.trim().isNotEmpty && !_emailValido(p.email.text))
                          ? 'Correo inválido' : null,
                      errorStyle: const TextStyle(fontSize: 10),
                      helperText: tipo == TipoDivision.partesIguales && _total > 0 && p.email.text.trim().isNotEmpty
                          ? '\$${(_total / _n).toStringAsFixed(2)} por persona' : null,
                      helperStyle: const TextStyle(color: AppTheme.success, fontSize: 10),
                      suffixIcon: p.email.text.trim().isEmpty
                          ? null
                          : Icon(
                              _emailValido(p.email.text) ? Icons.check_circle : Icons.error_outline,
                              color: _emailValido(p.email.text) ? AppTheme.success : AppTheme.warning,
                              size: 18,
                            ),
                    ),
                  ),
                ),
                if (tipo == TipoDivision.porPorcentaje) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: p.porcentaje,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}'))],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: '%',
                        suffixText: '%',
                        helperText: p.porcentaje.text.isNotEmpty && _total > 0
                            ? '\$${_montoParticipante(p).toStringAsFixed(2)}'
                            : null,
                        helperStyle: const TextStyle(color: AppTheme.success, fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                if (participantes.length > 1)
                  GestureDetector(
                    onTap: () => setState(() { p.dispose(); participantes.removeAt(i); }),
                    child: const Icon(Icons.remove_circle_outline, color: AppTheme.danger, size: 18),
                  )
                else
                  const SizedBox(width: 22),
              ]),
            );
          }),

          if (participantes.length < 4)
            TextButton.icon(
              onPressed: () => setState(() => participantes.add(SplitParticipante())),
              icon: const Icon(Icons.person_add_outlined, size: 15),
              label: const Text('Agregar participante', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
        ],
      ]),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;
  const _TipoChip({required this.label, required this.icono, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: seleccionado ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado ? AppTheme.primary : AppTheme.border,
            width: seleccionado ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icono, size: 14, color: seleccionado ? AppTheme.primary : AppTheme.textSecondary),
          const SizedBox(width: 5),
          Flexible(child: Text(
            label,
            style: TextStyle(
              color: seleccionado ? AppTheme.primary : AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: seleccionado ? FontWeight.w700 : FontWeight.normal,
            ),
          )),
        ]),
      ),
    ),
  );
}
