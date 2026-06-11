import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'assign_to_budget_screen.dart';
import 'create_expense_from_invoice_screen.dart';
import 'create_gustito_from_invoice_screen.dart';
import 'split_invoice_screen.dart';
import 'assign_service_expense_screen.dart';

class SelectTargetScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const SelectTargetScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  State<SelectTargetScreen> createState() => _SelectTargetScreenState();
}

class _SelectTargetScreenState extends State<SelectTargetScreen> {
  // M1 — dos niveles: el flujo feliz (gasto personal) es inmediato;
  // las opciones especializadas quedan bajo "Más opciones".
  bool _verMas = false;

  void _ir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final uid = widget.firebaseUid;

    // AD1 — colores mapeados a AppTheme (sin Colors.*Accent raw)
    final especializadas = <_Option>[
      _Option(Icons.receipt_long_outlined, 'Gasto existente', 'Marcar pago en tu presupuesto', AppTheme.primary,
          () => _ir(AssignToBudgetScreen(invoice: invoice, firebaseUid: uid))),
      _Option(Icons.star_outline, 'Gustito', 'Registrar como compra por gusto', AppTheme.colorAhorro,
          () => _ir(CreateGustitoFromInvoiceScreen(invoice: invoice, firebaseUid: uid))),
      _Option(Icons.people_outline, 'Presupuesto compartido', 'Dividir con tu pareja o grupo', AppTheme.success,
          () => _ir(SplitInvoiceScreen(invoice: invoice, firebaseUid: uid))),
      _Option(Icons.work_outline, 'Gasto operativo', 'Asociar a un trabajo/servicio', AppTheme.warning,
          () => _ir(AssignServiceExpenseScreen(invoice: invoice, firebaseUid: uid, tipo: 'gasto_operativo_servicio'))),
      _Option(Icons.business_center_outlined, 'Gasto empresarial', 'Gasto de tu negocio/empresa', AppTheme.info,
          () => _ir(AssignServiceExpenseScreen(invoice: invoice, firebaseUid: uid, tipo: 'gasto_empresarial'))),
      _Option(Icons.inventory_2_outlined, 'Compra de inventario', 'Registrar compra de stock', AppTheme.colorNoFijo,
          () => _ir(AssignServiceExpenseScreen(invoice: invoice, firebaseUid: uid, tipo: 'compra_inventario'))),
      _Option(Icons.save_outlined, 'Guardar sin asignar', 'Archivar en tu banco de facturas', AppTheme.textSecondary,
          () => Navigator.popUntil(context, (r) => r.isFirst)),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('¿Dónde asignar la factura?',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('B/. ${invoice['total_amount']?.toStringAsFixed(2) ?? '-'}  •  ${invoice['merchant_name'] ?? 'Factura'}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),

            if (!_verMas) ...[
              // ── Nivel 1: flujo feliz ──────────────────────────────────
              _BigOption(
                icon: Icons.add_circle_outline,
                title: 'Gasto personal',
                subtitle: 'Lo más común — regístralo en tu presupuesto del mes',
                color: AppTheme.primary,
                onTap: () => _ir(CreateExpenseFromInvoiceScreen(invoice: invoice, firebaseUid: uid)),
              ),
              const SizedBox(height: 12),
              _BigOption(
                icon: Icons.tune,
                title: 'Más opciones',
                subtitle: 'Gustito, compartido, negocio, inventario, archivar…',
                color: AppTheme.textSecondary,
                onTap: () => setState(() => _verMas = true),
                trailing: Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
            ] else ...[
              // ── Nivel 2: opciones especializadas ──────────────────────
              GestureDetector(
                onTap: () => setState(() => _verMas = false),
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Icon(Icons.arrow_back, color: AppTheme.primary, size: 16),
                    SizedBox(width: 6),
                    Text('Volver', style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: especializadas.length,
                  itemBuilder: (_, i) => _OptionCard(opt: especializadas[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Option {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Option(this.icon, this.title, this.subtitle, this.color, this.onTap);
}

class _BigOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;
  const _BigOption({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap, this.trailing,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
        ])),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}

class _OptionCard extends StatelessWidget {
  final _Option opt;
  const _OptionCard({required this.opt});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: opt.onTap,
    child: Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: opt.color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(opt.icon, color: opt.color, size: 32),
          const SizedBox(height: 8),
          Text(opt.title,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text(opt.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    ),
  );
}
