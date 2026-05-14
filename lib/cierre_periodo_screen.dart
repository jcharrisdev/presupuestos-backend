import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/income_service.dart';

class CierrePeriodoScreen extends StatefulWidget {
  final Map<String, dynamic> presupuesto;
  final Map<String, dynamic> periodo;
  final String firebaseUid;

  const CierrePeriodoScreen({
    super.key,
    required this.presupuesto,
    required this.periodo,
    required this.firebaseUid,
  });

  @override
  State<CierrePeriodoScreen> createState() => _CierrePeriodoScreenState();
}

class _CierrePeriodoScreenState extends State<CierrePeriodoScreen> {
  Map<String, dynamic>? _resumen;
  bool _loading = true;
  bool _cerrando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final presId  = widget.presupuesto['id'] as int;
    final perId   = widget.periodo['id'] as int;
    try {
      final data = await IncomeService.getResumenCierre(presId, perId, widget.firebaseUid);
      if (mounted) setState(() { _resumen = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _confirmarCierre() async {
    final presId = widget.presupuesto['id'] as int;
    final perId  = widget.periodo['id'] as int;
    setState(() => _cerrando = true);
    try {
      await IncomeService.cerrarPeriodo(presId, perId, widget.firebaseUid);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('ya fue cerrado')
            ? 'Este período ya fue cerrado'
            : 'Error al cerrar: $e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _cerrando = false);
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Cierre de período',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger),
                        textAlign: TextAlign.center),
                  ))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final r = _resumen!;
    final numPeriodo  = r['periodo']?['numero_periodo'] ?? '';
    final fechaIni    = r['periodo']?['fecha_inicio'] ?? '';
    final fechaFin    = r['periodo']?['fecha_fin'] ?? '';
    final tieneIncome = r['tiene_income'] == true;
    final ingresado   = _d(r['ingreso_neto']);
    final gastado     = _d(r['total_gastado_real']);
    final ahorro      = _d(r['total_ahorro']);
    final gustitos    = _d(r['total_gustitos']);
    final disponible  = _d(r['disponible_real']);
    final aprendizajes = (r['aprendizajes'] as List<dynamic>?)?.cast<String>() ?? [];
    final puedeCerrar = r['puede_cerrar_manualmente'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del período
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Período #$numPeriodo',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$fechaIni — $fechaFin',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cards de resumen
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              if (tieneIncome)
                _StatCard('Ingresaste', ingresado, AppTheme.success, Icons.arrow_downward),
              _StatCard('Gastaste', gastado, AppTheme.danger, Icons.arrow_upward),
              _StatCard('Ahorraste', ahorro, AppTheme.info, Icons.savings_outlined),
              _StatCard('Gustitos', gustitos, AppTheme.primary, Icons.bolt),
              _StatCard(
                disponible >= 0 ? 'Te quedaron' : 'Excediste',
                disponible.abs(),
                disponible >= 0 ? AppTheme.success : AppTheme.danger,
                disponible >= 0 ? Icons.check_circle_outline : Icons.warning_amber_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Aprendizajes
          if (aprendizajes.isNotEmpty) ...[
            const Text('Aprendizajes del período',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...aprendizajes.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
          ],

          // Botón de cierre
          if (puedeCerrar) ...[
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            const Text(
              'Al confirmar, el período actual se cerrará y se generará el siguiente automáticamente.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cerrando ? null : _confirmarCierre,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _cerrando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Confirmar cierre del período',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.textSecondary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El cierre manual estará disponible en los últimos 2 días del período.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double monto;
  final Color color;
  final IconData icon;

  const _StatCard(this.label, this.monto, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
          Text('\$${monto.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
