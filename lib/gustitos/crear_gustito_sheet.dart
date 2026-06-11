import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/gustitos_service.dart';
import '../widgets/financiero/categoria_selector.dart';
import '../utils/money.dart';

const _emociones = ['antojo', 'premio', 'social', 'impulso', 'estrés', 'otro'];

class CrearGustitoSheet {
  static void show(
    BuildContext context, {
    int? budgetId,
    required String firebaseUid,
    required VoidCallback onCreado,
  }) {
    final nameCtrl     = TextEditingController();
    final montoCtrl    = TextEditingController();
    final merchantCtrl = TextEditingController();
    String categoria = 'alimentacion';
    String? emocion;
    DateTime spentAt = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bolt, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nuevo Gustito',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('Compra consciente sin culpa',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 24),

                // Nombre
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: '¿Qué compraste?'),
                ),
                const SizedBox(height: 12),

                // Monto
                TextField(
                  controller: montoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration:
                      const InputDecoration(prefixText: 'B/. ', hintText: '0.00'),
                ),
                const SizedBox(height: 12),

                // Comercio (opcional)
                TextField(
                  controller: merchantCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                      hintText: 'Comercio o lugar (opcional)'),
                ),
                const SizedBox(height: 20),

                // Fecha
                Text('¿Cuándo?',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: spentAt,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: ColorScheme.dark(
                              primary: AppTheme.primary,
                              surface: AppTheme.surfaceAlt),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) setS(() => spentAt = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          color: AppTheme.textSecondary, size: 16),
                      const SizedBox(width: 10),
                      Text(
                        '${spentAt.year}-${spentAt.month.toString().padLeft(2, "0")}-${spentAt.day.toString().padLeft(2, "0")}',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 20),

                // Categoría
                Text('Categoría',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                CategoriaSelector(
                  firebaseUid: firebaseUid,
                  categoriaActual: categoria,
                  color: AppTheme.primary,
                  onChanged: (cat, custom) =>
                      setS(() => categoria = custom ?? cat),
                ),

                const SizedBox(height: 20),

                // Emoción
                Text('¿Cómo te sentiste? (opcional)',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ..._emociones.map((e) => GestureDetector(
                    onTap: () => setS(() => emocion = emocion == e ? null : e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: emocion == e
                            ? AppTheme.info.withOpacity(0.15)
                            : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: emocion == e
                              ? AppTheme.info
                              : AppTheme.border,
                        ),
                      ),
                      child: Text(e,
                          style: TextStyle(
                            color: emocion == e
                                ? AppTheme.info
                                : AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          )),
                    ),
                  )),
                ]),

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name  = nameCtrl.text.trim();
                      final monto = double.tryParse(montoCtrl.text) ?? 0;
                      if (name.isEmpty || monto <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Ingresa nombre y monto')));
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        await GustitosService.crear({
                          'user_id': firebaseUid,
                          if (budgetId != null) 'budget_id': budgetId,
                          'name': name,
                          'amount': monto,
                          'merchant': merchantCtrl.text.trim().isEmpty
                              ? null
                              : merchantCtrl.text.trim(),
                          'category': categoria,
                          'emotion_tag': emocion,
                          'source': 'manual',
                          'spent_at':
                              '${spentAt.year}-${spentAt.month.toString().padLeft(2, "0")}-${spentAt.day.toString().padLeft(2, "0")}',
                        });
                        onCreado();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Error al guardar el Gustito')));
                        }
                      }
                    },
                    child: const Text('Guardar Gustito'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
