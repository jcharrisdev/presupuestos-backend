import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/user_settings_service.dart';
import 'services/user_profile_service.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'tutorial_screen.dart';
import 'estado_financiero_anual_screen.dart';
import 'mes_detalle_screen.dart';
import 'deudas/deudas_screen.dart';
import 'perfil_financiero_screen.dart';
import 'shared_budgets_list_screen.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';
import 'invoice_scanner/invoice_history_screen.dart';
import 'dashboard_screen.dart';
import 'ventas_landing_screen.dart';
import 'patrimonio_screen.dart';
import 'objetivos_screen.dart';
import 'widgets/widgets.dart';
import 'widgets/financiero/agregar_gasto_sheet.dart';

class HomeShell extends StatefulWidget {
  final String firebaseUid;
  final String? displayName;
  final String? photoUrl;

  const HomeShell({
    Key? key,
    required this.firebaseUid,
    this.displayName,
    this.photoUrl,
  }) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;
  final Set<int> _initializedTabs = {0};
  bool _modoNegocio = false;
  String _periodo = 'mensual'; // 'mensual' | 'quincenal'
  bool _loadingSettings = true;
  bool _togglingNegocio = false;

  static const _mesesLabel = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

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
      _periodo = s['periodo_preferido'] as String? ?? 'mensual';
      _loadingSettings = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (income == null) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TutorialScreen(
            firebaseUid: uid,
            onDone: () {
              if (mounted) Navigator.push(context, MaterialPageRoute(
                builder: (_) => OnboardingScreen(firebaseUid: uid),
              ));
            },
          ),
        ));
      } else if (!TutorialScreen.isSeen(uid)) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TutorialScreen(firebaseUid: uid),
        ));
      }
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

  Future<void> _abrirRegistroRapido(BuildContext context, DateTime now) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgregarGastoSheet(
        firebaseUid: widget.firebaseUid,
        anio: now.year,
        mes: now.month,
      ),
    );
    if (res == true && _initializedTabs.contains(1)) {
      // Forzar recarga del tab Mes si está inicializado
      setState(() { _initializedTabs.remove(1); });
      Future.microtask(() => setState(() { _initializedTabs.add(1); }));
    }
  }

  Future<void> _logout() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid  = widget.firebaseUid;
    final now  = DateTime.now();

    final List<Widget> screens = [
      EstadoFinancieroAnualScreen(
        firebaseUid: uid,
        periodoInicial: _periodo,
        onPeriodoChanged: (p) {
          setState(() => _periodo = p);
          UserSettingsService.setPeriodo(uid, p);
        },
      ),
      MesDetalleScreen(
        firebaseUid: uid,
        anio: now.year,
        mes: now.month,
        label: _mesesLabel[now.month],
      ),
      DeudasScreen(firebaseUid: uid),
      _MasTab(
        firebaseUid: uid,
        displayName: widget.displayName,
        photoUrl: widget.photoUrl,
        modoNegocio: _modoNegocio,
        loadingSettings: _loadingSettings,
        togglingNegocio: _togglingNegocio,
        onToggleNegocio: _toggleNegocio,
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _idx,
        children: List.generate(screens.length, (i) =>
          _initializedTabs.contains(i) ? screens[i] : const SizedBox.shrink()),
      ),
      floatingActionButton: _idx != 3 ? FloatingActionButton(
        heroTag: 'fab_global',
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.background,
        onPressed: () => _abrirRegistroRapido(context, now),
        child: const Icon(Icons.add, size: 28),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() { _idx = i; _initializedTabs.add(i); }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Estado',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Mes actual',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon: Icon(Icons.credit_card),
            label: 'Deudas',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}

// ── Tab "Más" ─────────────────────────────────────────────────────────────────

class _MasTab extends StatelessWidget {
  final String firebaseUid;
  final String? displayName;
  final String? photoUrl;
  final bool modoNegocio;
  final bool loadingSettings;
  final bool togglingNegocio;
  final ValueChanged<bool> onToggleNegocio;
  final VoidCallback onLogout;

  const _MasTab({
    required this.firebaseUid,
    this.displayName,
    this.photoUrl,
    required this.modoNegocio,
    required this.loadingSettings,
    required this.togglingNegocio,
    required this.onToggleNegocio,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final name    = displayName ?? firebaseUid;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Salarying'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: onLogout,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header usuario ────────────────────────────────────────────
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                child: photoUrl == null
                    ? Text(initial, style: const TextStyle(
                        color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 18))
                    : null,
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bienvenido',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Text(
                  name.length > 24 ? '${name.substring(0, 24)}...' : name,
                  style: const TextStyle(color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ]),
            ]),

            const SizedBox(height: 28),
            const SectionHeader('MÓDULOS'),
            const SizedBox(height: 14),

            // ── Grid de módulos ───────────────────────────────────────────
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _ModuloCard(
                  icon: Icons.account_circle_outlined,
                  title: 'Perfil Financiero',
                  subtitle: 'Ingreso y gastos fijos',
                  color: AppTheme.success,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PerfilFinancieroScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.group_outlined,
                  title: 'Compartido',
                  subtitle: 'Gastos con roles',
                  color: AppTheme.info,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SharedBudgetsListScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.savings_outlined,
                  title: 'Ahorro y Metas',
                  subtitle: 'Objetivos financieros',
                  color: AppTheme.colorAhorro,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AhorroMetaScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.calendar_month_outlined,
                  title: 'Calendario',
                  subtitle: 'Pagos y vencimientos',
                  color: AppTheme.colorNoFijo,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CalendarioScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Facturas QR',
                  subtitle: 'Escanea recibos DGI',
                  color: AppTheme.primary,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => InvoiceHistoryScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.dashboard_outlined,
                  title: 'Dashboard',
                  subtitle: 'Resumen inteligente',
                  color: AppTheme.warning,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DashboardScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Patrimonio',
                  subtitle: 'Activos y pasivos',
                  color: AppTheme.info,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PatrimonioScreen(firebaseUid: firebaseUid),
                  )),
                ),
                _ModuloCard(
                  icon: Icons.flag_outlined,
                  title: 'Objetivos',
                  subtitle: 'Metas a largo plazo',
                  color: AppTheme.colorAhorro,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ObjetivosScreen(firebaseUid: firebaseUid),
                  )),
                ),
                if (modoNegocio)
                  _ModuloCard(
                    icon: Icons.storefront_outlined,
                    title: 'Ventas',
                    subtitle: 'Productos y servicios',
                    color: AppTheme.success,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => VentasLandingScreen(firebaseUid: firebaseUid),
                    )),
                  ),
              ],
            ),

            const SizedBox(height: 28),
            const SectionHeader('MODO DE USO'),
            const SizedBox(height: 12),

            // ── Toggle negocio ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: modoNegocio
                      ? AppTheme.success.withValues(alpha: 0.4)
                      : AppTheme.border,
                ),
              ),
              child: Row(children: [
                Icon(
                  modoNegocio ? Icons.storefront_outlined : Icons.person_outline,
                  color: modoNegocio ? AppTheme.success : AppTheme.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    modoNegocio ? 'Modo Negocio activo' : 'Solo finanzas personales',
                    style: TextStyle(
                      color: modoNegocio ? AppTheme.success : AppTheme.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    modoNegocio
                        ? 'Ventas y servicios habilitados'
                        : '¿Tienes un negocio? Actívalo aquí',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ])),
                togglingNegocio || loadingSettings
                    ? const SizedBox(width: 36, height: 20,
                        child: Center(child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2,
                                color: AppTheme.success))))
                    : Switch(
                        value: modoNegocio,
                        activeColor: AppTheme.success,
                        onChanged: onToggleNegocio,
                      ),
              ]),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

class _ModuloCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModuloCard({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
          Text(subtitle, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10)),
        ]),
      ]),
    ),
  );
}
