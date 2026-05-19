import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'theme/app_theme.dart';
import 'estado_financiero_anual_screen.dart';
import 'perfil_financiero_screen.dart';
import 'shared_budgets_list_screen.dart';
import 'invoice_scanner/invoice_history_screen.dart';

class TutorialScreen extends StatefulWidget {
  final String firebaseUid;
  final VoidCallback? onDone;
  const TutorialScreen({super.key, required this.firebaseUid, this.onDone});

  static String _key(String uid) => 'tutorial_visto_$uid';
  static bool isSeen(String uid) =>
      Hive.box('salarying_cache').get(_key(uid), defaultValue: false) as bool;
  static void markSeen(String uid) =>
      Hive.box('salarying_cache').put(_key(uid), true);

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _ctrl = PageController();
  int _paso = 0;

  static const _pasos = [
    _Paso(
      color:    AppTheme.primary,
      icon:     Icons.waving_hand_outlined,
      titulo:   '¡Bienvenido a Salarying!',
      desc:     'Tu app de finanzas personales. En menos de 2 minutos verás todo lo que puedes hacer aquí.',
      puntos:   [],
      accion:   null,
    ),
    _Paso(
      color:    AppTheme.primary,
      icon:     Icons.bar_chart_rounded,
      titulo:   'Estado Financiero Anual',
      desc:     'Tu pantalla principal. Muestra los 12 meses del año con cuánto ganas, gastas y te queda.',
      puntos:   [
        'Toca un mes para ver el detalle completo.',
        'El mes actual se marca con "HOY".',
        'Los meses en rojo significa que gastaste más de lo que entraste.',
        'Puedes ver la vista quincenal, mensual o anual.',
      ],
      accion:   _Accion('Ver mi Estado Financiero', Icons.bar_chart_rounded),
    ),
    _Paso(
      color:    AppTheme.success,
      icon:     Icons.account_circle_outlined,
      titulo:   'Mi Perfil Financiero',
      desc:     'Aquí defines tu ingreso y todos tus gastos fijos mensuales. El sistema los proyecta automáticamente en tus 12 meses.',
      puntos:   [
        'Actualiza tu ingreso si cambia.',
        'Agrega o elimina gastos fijos cuando quieras.',
        'Los cambios se reflejan en todos los meses futuros.',
      ],
      accion:   _Accion('Ir a Mi Perfil', Icons.account_circle_outlined),
    ),
    _Paso(
      color:    AppTheme.info,
      icon:     Icons.group_outlined,
      titulo:   'Presupuesto Compartido',
      desc:     'Compartes apartamento, carro o gastos con alguien. Aquí defines quién paga qué y la app lleva el balance automáticamente.',
      puntos:   [
        'Crea un presupuesto e invita a los demás por email.',
        'Cada persona ve solo lo que le toca pagar.',
        'Puedes liquidar el balance con un toque.',
        'Los pagos que hagas se registran en tu estado financiero.',
      ],
      accion:   _Accion('Ver Presupuestos Compartidos', Icons.group_outlined),
    ),
    _Paso(
      color:    AppTheme.warning,
      icon:     Icons.qr_code_scanner,
      titulo:   'Facturas QR',
      desc:     'Escanea los códigos QR de los recibos DGI de Panamá. La app extrae los datos y los asigna a tu mes.',
      puntos:   [
        'Escanea o sube imagen del recibo.',
        'Vincula la factura a un gasto del mes (gasolina, supermercado, etc.).',
        'Salarying aprende tus patrones y sugiere ajustes de presupuesto.',
      ],
      accion:   _Accion('Ir a Facturas QR', Icons.qr_code_scanner),
    ),
    _Paso(
      color:    AppTheme.colorAhorro,
      icon:     Icons.savings_outlined,
      titulo:   'Ahorro, Deudas y más',
      desc:     'El menú principal tiene todo lo que necesitas para controlar tus finanzas.',
      puntos:   [
        'Ahorro y Metas — define cuánto ahorrar y para qué.',
        'Mis Deudas — lleva el control de tarjetas y préstamos.',
        'Calendario — pagos y vencimientos por fecha.',
        'Dashboard — resumen inteligente con score de salud financiera.',
      ],
      accion:   _Accion('¡Empezar ahora!', Icons.rocket_launch_outlined),
    ),
  ];

  void _cerrar() {
    TutorialScreen.markSeen(widget.firebaseUid);
    Navigator.pop(context);
    widget.onDone?.call();
  }

  void _siguiente() {
    if (_paso < _pasos.length - 1) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _paso++);
    } else {
      _cerrar();
    }
  }

  void _navegarAccion(int idx) {
    _cerrar();
    Widget? dest;
    switch (idx) {
      case 1: dest = EstadoFinancieroAnualScreen(firebaseUid: widget.firebaseUid); break;
      case 2: dest = PerfilFinancieroScreen(firebaseUid: widget.firebaseUid); break;
      case 3: dest = SharedBudgetsListScreen(firebaseUid: widget.firebaseUid); break;
      case 4: dest = InvoiceHistoryScreen(firebaseUid: widget.firebaseUid); break;
      default: return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => dest!));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final paso = _pasos[_paso];
    final esUltimo = _paso == _pasos.length - 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              // Dots de progreso
              Expanded(
                child: Row(children: List.generate(_pasos.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 5),
                  width: i == _paso ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _paso ? paso.color : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ))),
              ),
              TextButton(
                onPressed: _cerrar,
                style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
                child: const Text('Saltar', style: TextStyle(fontSize: 13)),
              ),
            ]),
          ),

          // ── Contenido ────────────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _paso = i),
              itemCount: _pasos.length,
              itemBuilder: (_, i) => _PasoView(
                paso: _pasos[i],
                isActive: i == _paso,
              ),
            ),
          ),

          // ── Botones ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(children: [
              // Acción secundaria (ir a pantalla)
              if (paso.accion != null && !esUltimo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(paso.accion!.icon, size: 16),
                      label: Text(paso.accion!.label),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: paso.color,
                        side: BorderSide(color: paso.color.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _navegarAccion(_paso),
                    ),
                  ),
                ),
              // Botón principal
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: esUltimo
                      ? const Icon(Icons.rocket_launch_outlined, size: 18, color: Colors.black)
                      : const Icon(Icons.arrow_forward, size: 18, color: Colors.black),
                  label: Text(
                    esUltimo ? '¡Empezar!' : 'Siguiente',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: paso.color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _siguiente,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Paso view ─────────────────────────────────────────────────────────────────

class _PasoView extends StatelessWidget {
  final _Paso paso;
  final bool isActive;
  const _PasoView({required this.paso, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icono ilustrativo
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            width: isActive ? 100 : 80,
            height: isActive ? 100 : 80,
            decoration: BoxDecoration(
              color: paso.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: paso.color.withValues(alpha: 0.3), width: 2),
            ),
            child: Icon(paso.icon, color: paso.color, size: isActive ? 48 : 38),
          ),
        ),
        const SizedBox(height: 28),

        // Título
        Text(paso.titulo,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 12),

        // Descripción
        Text(paso.desc,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.6)),

        // Puntos
        if (paso.puntos.isNotEmpty) ...[
          const SizedBox(height: 20),
          ...paso.puntos.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 6, height: 6,
                decoration: BoxDecoration(color: paso.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(p,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5))),
            ]),
          )),
        ],
      ]),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _Paso {
  final Color color;
  final IconData icon;
  final String titulo;
  final String desc;
  final List<String> puntos;
  final _Accion? accion;
  const _Paso({
    required this.color, required this.icon, required this.titulo,
    required this.desc, required this.puntos, required this.accion,
  });
}

class _Accion {
  final String label;
  final IconData icon;
  const _Accion(this.label, this.icon);
}
