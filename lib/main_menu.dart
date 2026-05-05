import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'login_screen.dart';
import 'cobros_home.dart';
import 'services/auth_service.dart';
import 'dashboard_screen.dart';

/// Menú principal (home) de Salarying.
///
/// [firebaseUid] es el email de la cuenta Google; se propaga a todas las
/// sub-pantallas para filtrar datos por usuario en el backend.
/// [displayName] y [photoUrl] se usan solo para el avatar/header del menú.
class MainMenu extends StatelessWidget {
  final String firebaseUid;
  final String? displayName;
  final String? photoUrl;

  const MainMenu({
    Key? key,
    required this.firebaseUid,
    this.displayName,
    this.photoUrl,
  }) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? firebaseUid;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Salarying'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Panel principal',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text(
                  'Esta es la pantalla de inicio de Salarying.\n\n'
                  '1. Mis Presupuestos — registra y controla tus gastos por período (quincenal o mensual).\n'
                  '2. Ahorro y Metas — define metas de ahorro y sigue su progreso.\n'
                  '3. Calendario — ve todos tus pagos y cobros programados en un calendario.\n'
                  '4. Cobros — gestiona producción, ventas y cobros a clientes.\n\n'
                  'Toca cualquier tarjeta para entrar al módulo.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => _logout(context),
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
              // ── HEADER USUARIO ────────────────────────────────────────────
              Row(
                children: [
                  // Avatar: foto de Google si está disponible, si no inicial
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                    child: photoUrl == null
                        ? Text(initial, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bienvenido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(
                        name.length > 24 ? '${name.substring(0, 24)}...' : name,
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),
              const Text('PANEL PRINCIPAL', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),

              _NavCard(
                icon: Icons.dashboard_outlined,
                title: 'Dashboard',
                subtitle: 'Resumen de tu actividad',
                color: AppTheme.primary,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DashboardScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              _NavCard(
                icon: Icons.attach_money,
                title: 'Cobros',
                subtitle: 'Producción, ventas y cobros a clientes',
                color: AppTheme.success,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CobrosHome(firebaseUid: firebaseUid),
                )),
              ),

              const SizedBox(height: 32),

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
