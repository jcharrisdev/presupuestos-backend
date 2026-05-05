import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

class PagoFormSheet {
  static void show(
    BuildContext context, {
    required double sugerido,
    required void Function(double) onPagar,
  }) {
    final ctrl = TextEditingController(text: sugerido.toStringAsFixed(2));
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Registrar pago',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          const Text('Ingresa el monto real pagado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              final m = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
              if (m <= 0) return;
              Navigator.pop(context);
              onPagar(m);
            },
            child: const Text('Confirmar pago'),
          )),
        ]),
      ),
    );
  }
}
