import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'login_screen.dart';
import 'ventas_landing_screen.dart';
import 'shared_budgets_list_screen.dart';
import 'services/auth_service.dart';
import 'dashboard_screen.dart';
import 'widgets/widgets.dart';
import 'invoice_scanner/invoice_history_screen.dart';
import 'deudas/deudas_screen.dart';
import 'perfil_financiero_screen.dart';
import 'estado_financiero_anual_screen.dart';
import 'debug_logs_screen.dart';

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
                  '1. Presupuesto — Individual (tus gastos personales) o Compartido (con otra persona).\n'
                  '2. Ahorro y Metas — define metas de ahorro y sigue su progreso.\n'
                  '3. Calendario — ve todos tus pagos y cobros programados.\n'
                  '4. Ventas — elige entre Venta de productos (catálogo, producción y cobros) u Ofrecimiento de servicios (trabajos con colaboradores y utilidad neta).\n\n'
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
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                  child: photoUrl == null
                      ? Text(initial,
                          style: const TextStyle(
                              color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18))
                      : null,
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Bienvenido',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text(
                    name.length > 24 ? '${name.substring(0, 24)}...' : name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ]),
              ]),

              const SizedBox(height: 32),
              const SectionHeader('PANEL PRINCIPAL'),
              const SizedBox(height: 14),

              // ── ESTADO FINANCIERO ANUAL — PANTALLA PRINCIPAL ─────────────
              _NavCard(
                icon: Icons.bar_chart_rounded,
                title: 'Estado Financiero Anual',
                subtitle: 'Tu panorama completo: ingresos, gastos y remanente mes a mes',
                color: AppTheme.primary,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EstadoFinancieroAnualScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),

              _NavCard(
                icon: Icons.dashboard_outlined,
                title: 'Dashboard',
                subtitle: 'Resumen financiero inteligente',
                color: AppTheme.info,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DashboardScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),

              // ── PERFIL FINANCIERO ──────────────────────────────────────────
              _NavCard(
                icon: Icons.account_circle_outlined,
                title: 'Mi Perfil Financiero',
                subtitle: 'Ingreso · Gastos fijos · Gastos variables base',
                color: AppTheme.success,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PerfilFinancieroScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),

              // ── PRESUPUESTO EXPANDIBLE ────────────────────────────────────
              _PresupuestoExpandCard(firebaseUid: firebaseUid),

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
                icon: Icons.credit_card_outlined,
                title: 'Mis Deudas',
                subtitle: 'Tarjetas, préstamos y saldo pendiente',
                color: AppTheme.danger,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DeudasScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
              _NavCard(
                icon: Icons.storefront_outlined,
                title: 'Ventas',
                subtitle: 'Venta de productos y ofrecimiento de servicios',
                color: AppTheme.success,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VentasLandingScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
              _NavCard(
                icon: Icons.qr_code_scanner,
                title: 'Facturas QR',
                subtitle: 'Escanea y asigna facturas electrónicas DGI',
                color: AppTheme.primary,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => InvoiceHistoryScreen(firebaseUid: firebaseUid),
                )),
              ),

              const SizedBox(height: 32),
              const SectionHeader('ESTADO DEL SISTEMA'),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  const Text('Backend conectado',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const Spacer(),
                  const Text('Clever Cloud · MySQL',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const DebugLogsScreen(),
                )),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Row(children: [
                    Icon(Icons.bug_report_outlined, color: AppTheme.textMuted, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Logs del servidor',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text('Ver errores recientes del backend',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    ])),
                    Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 16),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Presupuesto expandible ─────────────────────────────────────────────────────

class _PresupuestoExpandCard extends StatefulWidget {
  final String firebaseUid;
  const _PresupuestoExpandCard({required this.firebaseUid});

  @override
  State<_PresupuestoExpandCard> createState() => _PresupuestoExpandCardState();
}

class _PresupuestoExpandCardState extends State<_PresupuestoExpandCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animCtrl;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _rotate = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _animCtrl.forward() : _animCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Tarjeta principal ──────────────────────────────────────────
      GestureDetector(
        onTap: _toggle,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _expanded ? AppTheme.colorFijo.withOpacity(0.5) : AppTheme.border,
            ),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppTheme.colorFijo.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  color: AppTheme.colorFijo, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Presupuesto',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 3),
              const Text('Individual o compartido',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ])),
            RotationTransition(
              turns: _rotate,
              child: const Icon(Icons.expand_more, color: AppTheme.textMuted, size: 20),
            ),
          ]),
        ),
      ),

      // ── Sub-opciones animadas ──────────────────────────────────────
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: _expanded
            ? Padding(
                padding: const EdgeInsets.only(top: 8, left: 16),
                child: Column(children: [
                  _SubCard(
                    icon: Icons.person_outline,
                    title: 'Presupuesto Individual',
                    subtitle: 'Controla tus gastos por período',
                    color: AppTheme.colorFijo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ListaPresupuestos(firebaseUid: widget.firebaseUid),
                    )),
                  ),
                  const SizedBox(height: 8),
                  _SubCard(
                    icon: Icons.group_outlined,
                    title: 'Presupuesto Compartido',
                    subtitle: 'Gastos con otra persona',
                    color: AppTheme.info,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SharedBudgetsListScreen(firebaseUid: widget.firebaseUid),
                    )),
                  ),
                ]),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

// ── Sub-card ───────────────────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SubCard({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 16),
        ]),
      ),
    );
  }
}

// ── NavCard principal ──────────────────────────────────────────────────────────

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
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
        ]),
      ),
    );
  }
}
