import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'assign_to_budget_screen.dart';
import 'create_expense_from_invoice_screen.dart';
import 'create_gustito_from_invoice_screen.dart';
import 'split_invoice_screen.dart';
import 'assign_service_expense_screen.dart';

class SelectTargetScreen extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String firebaseUid;
  const SelectTargetScreen({super.key, required this.invoice, required this.firebaseUid});

  @override
  Widget build(BuildContext context) {
    final options = [
      _Option(Icons.receipt_long_outlined,    'Gasto existente',         'Marcar pago en tu presupuesto',         AppTheme.primary,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignToBudgetScreen(invoice: invoice, firebaseUid: firebaseUid)))),
      _Option(Icons.add_circle_outline,       'Gasto nuevo',             'Crear gasto en tu presupuesto',         Colors.blueAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateExpenseFromInvoiceScreen(invoice: invoice, firebaseUid: firebaseUid)))),
      _Option(Icons.star_outline,             'Gustito',                 'Registrar como compra por gusto',       Colors.purpleAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateGustitoFromInvoiceScreen(invoice: invoice, firebaseUid: firebaseUid)))),
      _Option(Icons.people_outline,           'Presupuesto compartido',  'Dividir con tu pareja o grupo',         Colors.tealAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => SplitInvoiceScreen(invoice: invoice, firebaseUid: firebaseUid)))),
      _Option(Icons.work_outline,             'Gasto operativo',         'Asociar a un trabajo/servicio',         Colors.orangeAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignServiceExpenseScreen(invoice: invoice, firebaseUid: firebaseUid, tipo: 'gasto_operativo_servicio')))),
      _Option(Icons.business_center_outlined, 'Gasto empresarial',       'Gasto de tu negocio/empresa',           Colors.cyan,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignServiceExpenseScreen(invoice: invoice, firebaseUid: firebaseUid, tipo: 'gasto_empresarial')))),
      _Option(Icons.inventory_2_outlined,     'Compra de inventario',    'Registrar compra de stock',             Colors.lime,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignServiceExpenseScreen(invoice: invoice, firebaseUid: firebaseUid, tipo: 'compra_inventario')))),
      _Option(Icons.save_outlined,            'Guardar sin asignar',     'Archivar en tu banco de facturas',      AppTheme.textSecondary,
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
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemCount: options.length,
                itemBuilder: (_, i) => _OptionCard(opt: options[i]),
              ),
            ),
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
        border: Border.all(color: opt.color.withOpacity(0.3)),
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
