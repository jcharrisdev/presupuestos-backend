import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'cobros_home.dart';
import 'servicios/servicios_dashboard.dart';

class VentasLandingScreen extends StatelessWidget {
  final String firebaseUid;
  const VentasLandingScreen({Key? key, required this.firebaseUid}) : super(key: key);

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Módulo de Ventas',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Este módulo agrupa dos divisiones comerciales independientes:\n\n'
          '1. Venta de productos — gestiona tu catálogo, producción y cobros a clientes por productos.\n\n'
          '2. Ofrecimiento de servicios — crea trabajos o proyectos, registra clientes, asigna colaboradores, '
          'registra pagos y gastos, y calcula tu utilidad neta.\n\n'
          'Selecciona la división con la que deseas trabajar.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Ayuda',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Con qué deseas trabajar hoy?',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecciona una de las dos divisiones comerciales.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 28),
              _DivisionCard(
                icon: Icons.storefront_outlined,
                titulo: 'Venta de productos',
                subtitulo: 'Catálogo, producción, inventario y cobros a clientes.',
                color: AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CobrosHome(firebaseUid: firebaseUid)),
                ),
              ),
              const SizedBox(height: 16),
              _DivisionCard(
                icon: Icons.handshake_outlined,
                titulo: 'Ofrecimiento de servicios',
                subtitulo: 'Trabajos, proyectos y producciones operativas con colaboradores.',
                color: const Color(0xFF0EA5E9),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ServiciosDashboard(firebaseUid: firebaseUid)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DivisionCard extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _DivisionCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: color.withOpacity(0.7), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
