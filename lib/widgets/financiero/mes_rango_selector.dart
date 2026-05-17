import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Selector visual de rango de meses (desde/hasta).
/// Devuelve mesInicio y mesFin como int (1-12).
///
/// Uso:
///   MesRangoSelector(
///     mesInicio: 3, mesFin: 8,
///     onChange: (inicio, fin) => setState(() { ... }),
///   )
class MesRangoSelector extends StatelessWidget {
  final int mesInicio;
  final int mesFin;
  final void Function(int inicio, int fin) onChange;

  const MesRangoSelector({
    Key? key,
    required this.mesInicio,
    required this.mesFin,
    required this.onChange,
  }) : super(key: key);

  static const _meses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('PERÍODO DE VIGENCIA',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _DropMes(
          label: 'Desde',
          valor: mesInicio,
          onChanged: (v) => onChange(v, mesFin < v ? v : mesFin),
        )),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('→', style: TextStyle(color: AppTheme.textMuted, fontSize: 18)),
        ),
        Expanded(child: _DropMes(
          label: 'Hasta',
          valor: mesFin,
          onChanged: (v) => onChange(mesInicio > v ? v : mesInicio, v),
        )),
      ]),
      const SizedBox(height: 4),
      if (mesInicio == 1 && mesFin == 12)
        const Text('Aplica todo el año', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))
      else
        Text(
          'Aplica de ${_meses[mesInicio - 1]} a ${_meses[mesFin - 1]} (${mesFin - mesInicio + 1} meses)',
          style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
    ]);
  }

  static String nombreMes(int m) => _meses[m - 1];
}

class _DropMes extends StatelessWidget {
  final String label;
  final int valor;
  final void Function(int) onChanged;
  const _DropMes({required this.label, required this.valor, required this.onChanged});

  static const _meses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: valor,
      decoration: InputDecoration(labelText: label),
      dropdownColor: AppTheme.surfaceAlt,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      items: List.generate(12, (i) => DropdownMenuItem(
        value: i + 1,
        child: Text(_meses[i]),
      )),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}
