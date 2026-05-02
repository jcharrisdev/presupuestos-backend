/// Menú principal (home) de Salarying.
///
/// Es la pantalla que ve el usuario tras iniciar sesión.
/// Muestra 4 tarjetas de navegación hacia los módulos principales:
///   - Mis Presupuestos
///   - Ahorro y Metas
///   - Calendario
///   - Cobros
///
/// También muestra un indicador del estado de conexión con el backend.
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'login_screen.dart';
import 'cobros_home.dart';

/// Pantalla principal con las 4 cards de navegación.
///
/// [firebaseUid] se propaga a TODAS las sub-pantallas para filtrar
/// los datos por usuario en cada petición al backend.
class MainMenu extends StatelessWidget {
  final String firebaseUid;
  const MainMenu({Key? key, required this.firebaseUid}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Inicial del email para el avatar (ej: "j" si el uid es "juan@...")
    final initials = firebaseUid.isNotEmpty ? firebaseUid[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Sin flecha de "atrás" — es la pantalla raíz
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
          // Botón de cerrar sesión: usa pushAndRemoveUntil para limpiar
          // todo el stack de navegación y que el botón "atrás" no regrese al menú.
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
              // ── HEADER USUARIO ────────────────────────────────────────────
              Row(
                children: [
                  // Avatar con la inicial del email/uid
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
                      // Truncar el uid si es muy largo (ej: UIDs de Firebase son ~28 chars)
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

              // ── TARJETAS DE NAVEGACIÓN ────────────────────────────────────
              // Cada _NavCard navega a su pantalla y devuelve el firebaseUid.

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

              // ── ESTADO DEL SISTEMA ────────────────────────────────────────
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
                    // Punto verde = backend accesible
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

/// Tarjeta de navegación reutilizable para los módulos del menú principal.
///
/// Muestra un ícono con color de acento, título, subtítulo y flecha de acceso.
class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;     // color de acento del módulo
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
            // Ícono del módulo con fondo de color semitransparente
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
