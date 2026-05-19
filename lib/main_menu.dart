import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'login_screen.dart';
import 'ventas_landing_screen.dart';
import 'shared_budgets_list_screen.dart';
import 'services/auth_service.dart';
import 'services/user_settings_service.dart';
import 'services/user_profile_service.dart';
import 'onboarding_screen.dart';
import 'dashboard_screen.dart';
import 'widgets/widgets.dart';
import 'invoice_scanner/invoice_history_screen.dart';
import 'deudas/deudas_screen.dart';
import 'perfil_financiero_screen.dart';
import 'estado_financiero_anual_screen.dart';
import 'debug_logs_screen.dart';
import 'tutorial_screen.dart';

class MainMenu extends StatefulWidget {
  final String firebaseUid;
  final String? displayName;
  final String? photoUrl;

  const MainMenu({
    Key? key,
    required this.firebaseUid,
    this.displayName,
    this.photoUrl,
  }) : super(key: key);

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  bool _modoNegocio = false;
  bool _loadingSettings = true;
  bool _togglingNegocio = false;

  @override
  void initState() {
    super.initState();
    _cargarSettings();
  }

  Future<void> _cargarSettings() async {
    final uid = widget.firebaseUid;
    final (s, income) = await (
      UserSettingsService.get(uid),
      UserProfileService.getIncome(uid),
    ).wait;
    if (!mounted) return;
    setState(() {
      _modoNegocio = (s['modo_negocio'] as int? ?? 0) == 1;
      _loadingSettings = false;
    });

    // ── Flujo de primera vez ──────────────────────────────────────────
    // Orden: Tutorial → Onboarding → App libre
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!TutorialScreen.isSeen(uid)) {
        // Primera vez absoluta: tutorial primero, luego onboarding si falta income
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TutorialScreen(
            firebaseUid: uid,
            onDone: income == null ? () {
              if (mounted) Navigator.push(context, MaterialPageRoute(
                builder: (_) => OnboardingScreen(firebaseUid: uid),
              ));
            } : null,
          ),
        ));
      } else if (income == null) {
        // Ya vio el tutorial pero nunca configuró income (regresó sin terminar)
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => OnboardingScreen(firebaseUid: uid),
        ));
      }
      // else: usuario normal — nada que mostrar
    });
  }

  Future<void> _toggleNegocio(bool valor) async {
    setState(() => _togglingNegocio = true);
    final ok = await UserSettingsService.setModoNegocio(widget.firebaseUid, valor);
    if (mounted) setState(() {
      if (ok) _modoNegocio = valor;
      _togglingNegocio = false;
    });
  }

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
    final firebaseUid = widget.firebaseUid;
    final name = widget.displayName ?? firebaseUid;
    final photoUrl = widget.photoUrl;
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
                  '1. Estado Financiero Anual — tu panorama financiero completo del año.\n'
                  '2. Perfil Financiero — configura tu ingreso y gastos fijos.\n'
                  '3. Presupuesto Compartido — gastos con roles y balance entre personas.\n'
                  '4. Ahorro y Metas — define y sigue tus objetivos financieros.\n'
                  '5. Facturas QR — escanea recibos DGI y registra tus compras.\n\n'
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
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
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

              _NavCard(
                icon: Icons.group_outlined,
                title: 'Presupuesto Compartido',
                subtitle: 'Gastos compartidos con roles y balance',
                color: AppTheme.info,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SharedBudgetsListScreen(firebaseUid: firebaseUid),
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
                icon: Icons.credit_card_outlined,
                title: 'Mis Deudas',
                subtitle: 'Tarjetas, préstamos y saldo pendiente',
                color: AppTheme.danger,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DeudasScreen(firebaseUid: firebaseUid),
                )),
              ),
              const SizedBox(height: 12),
              if (_modoNegocio)
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
              const SectionHeader('MODO DE USO'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _modoNegocio ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.border,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _modoNegocio ? Icons.storefront_outlined : Icons.person_outline,
                    color: _modoNegocio ? AppTheme.success : AppTheme.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _modoNegocio ? 'Modo Negocio activo' : 'Solo finanzas personales',
                      style: TextStyle(
                        color: _modoNegocio ? AppTheme.success : AppTheme.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _modoNegocio
                          ? 'Ventas y servicios habilitados'
                          : '¿Tienes un negocio? Actívalo aquí',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ])),
                  _togglingNegocio || _loadingSettings
                      ? const SizedBox(width: 36, height: 20,
                          child: Center(child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.success))))
                      : Switch(
                          value: _modoNegocio,
                          activeColor: AppTheme.success,
                          onChanged: _toggleNegocio,
                        ),
                ]),
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

