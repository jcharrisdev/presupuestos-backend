import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class CalendarioScreen extends StatelessWidget {
  const CalendarioScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_month_outlined, size: 72, color: AppTheme.textMuted.withOpacity(0.4)),
          const SizedBox(height: 20),
          const Text('Próximamente', style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Vista de pagos y vencimientos del período', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ]),
      ),
    );
  }
}
