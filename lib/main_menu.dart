import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'login_screen.dart';

class MainMenu extends StatelessWidget {
  final String firebaseUid;
  const MainMenu({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final initials = firebaseUid.isNotEmpty ? firebaseUid[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Salarying'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            ),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header usuario
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                    radius: 22,
                    child: Text(
                      initials,
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bienvenido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(
                        firebaseUid.length > 24 ? '${firebaseUid.substring(0, 24)}...' : firebaseUid,
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),
              const Text('PANEL PRINCIPAL', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),

              // Cards de navegación
              _NavCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Mis Presupuestos',
                subtitle: 'Controla tus gastos por período',
                color: AppTheme.colorFijo,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ListaPresupuestos(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
              _NavCard(
                icon: Icons.savings_outlined,
                title: 'Ahorro y Metas',
                subtitle: 'Define y sigue tus objetivos financieros',
                color: AppTheme.colorAhorro,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AhorroMetaScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
              _NavCard(
                icon: Icons.calendar_month_outlined,
                title: 'Calendario',
                subtitle: 'Vista de pagos y vencimientos',
                color: AppTheme.colorNoFijo,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CalendarioScreen(firebaseUid: firebaseUid),
                )),
              ),

              const SizedBox(height: 32),

              // Info cards
              const Text('ESTADO DEL SISTEMA', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    const Text('Backend conectado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const Spacer(),
                    const Text('Clever Cloud · MySQL', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

