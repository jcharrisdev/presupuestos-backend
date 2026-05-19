import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AyudaSheet extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final List<AyudaItem> items;

  const AyudaSheet({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.items,
  });

  static void show(BuildContext context, {
    required String titulo,
    required String subtitulo,
    required List<AyudaItem> items,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => AyudaSheet(titulo: titulo, subtitulo: subtitulo, items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)))),
          // Header
          Row(children: [
            const Icon(Icons.help_outline, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(titulo,
                style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(subtitulo,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 8),
          // Items
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.titulo,
                    style: const TextStyle(color: AppTheme.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(item.desc,
                    style: const TextStyle(color: AppTheme.textSecondary,
                        fontSize: 12, height: 1.4)),
              ])),
            ]),
          )),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ),
        ]),
      ),
    );
  }
}

class AyudaItem {
  final IconData icon;
  final String titulo;
  final String desc;
  const AyudaItem(this.icon, this.titulo, this.desc);
}
