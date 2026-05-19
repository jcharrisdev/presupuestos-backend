import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/user_profile_service.dart';
import 'services/estado_anual_service.dart';
import 'estado_financiero_anual_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final String firebaseUid;
  const OnboardingScreen({super.key, required this.firebaseUid});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _paso = 0;

  // ── Paso 1: Ingreso ──────────────────────────────────────────────
  String _tipoIngreso = 'salario';
  final _brutoCtrl = TextEditingController();
  final _netoCtrl  = TextEditingController();
  String _frecuencia = 'mensual';
  bool _guardandoIncome = false;

  // ── Paso 2: Gastos fijos ─────────────────────────────────────────
  final List<Map<String, dynamic>> _gastosFijos = [];
  bool _guardandoGastos = false;

  // ── Paso 3: Generar ──────────────────────────────────────────────
  bool _generando = false;

  final _fmt = NumberFormat('#,##0.00', 'en_US');

  static const _sugerencias = [
    {'nombre': 'Alquiler',      'icon': Icons.home_outlined},
    {'nombre': 'Carro',         'icon': Icons.directions_car_outlined},
    {'nombre': 'Electricidad',  'icon': Icons.bolt_outlined},
    {'nombre': 'Agua',          'icon': Icons.water_drop_outlined},
    {'nombre': 'Internet',      'icon': Icons.wifi_outlined},
    {'nombre': 'Celular',       'icon': Icons.phone_android_outlined},
    {'nombre': 'Seguro',        'icon': Icons.health_and_safety_outlined},
    {'nombre': 'Alimentación',  'icon': Icons.restaurant_outlined},
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    _brutoCtrl.dispose();
    _netoCtrl.dispose();
    super.dispose();
  }

  double get _netoEstimado {
    final bruto = double.tryParse(_brutoCtrl.text) ?? 0;
    if (bruto <= 0) return 0;
    // CSS 9.75% + Educativo 1.25% = 11%
    return bruto * 0.89;
  }

  double get _ingresoNeto {
    if (_tipoIngreso == 'salario') return _netoEstimado;
    return double.tryParse(_netoCtrl.text) ?? 0;
  }

  double get _totalFijos => _gastosFijos.fold(0.0, (s, g) => s + (g['monto'] as double));
  double get _remanente  => _ingresoNeto - _totalFijos;

  void _irSiguiente() {
    if (_paso < 2) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _paso++);
    }
  }

  void _irAtras() {
    if (_paso > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _paso--);
    }
  }

  Future<void> _guardarIncome() async {
    final neto = _ingresoNeto;
    if (neto <= 0) { _snack('Ingresa un monto válido'); return; }
    setState(() => _guardandoIncome = true);
    try {
      await UserProfileService.upsertIncome(widget.firebaseUid, {
        'tipo_ingreso': _tipoIngreso,
        'ingreso_bruto_mensual': _tipoIngreso == 'salario'
            ? (double.tryParse(_brutoCtrl.text) ?? neto)
            : neto,
        'ingreso_neto_mensual': neto,
        'calcular_automatico': _tipoIngreso == 'salario' ? 1 : 0,
        'frecuencia_cobro': _frecuencia,
      });
      _irSiguiente();
    } catch (e) {
      _snack('Error al guardar: $e');
    }
    if (mounted) setState(() => _guardandoIncome = false);
  }

  Future<void> _agregarGastoFijo(String nombre, double monto) async {
    setState(() => _guardandoGastos = true);
    try {
      await UserProfileService.crearGastoFijo(widget.firebaseUid, {
        'descripcion': nombre,
        'monto_mensual': monto,
        'tipo': 'fijo',
        'clasificacion': 'esencial',
        'frecuencia': 'fijo',
        'activo': 1,
      });
      setState(() => _gastosFijos.add({'nombre': nombre, 'monto': monto}));
    } catch (e) {
      _snack('Error al guardar gasto');
    }
    if (mounted) setState(() => _guardandoGastos = false);
  }

  Future<void> _generarEstado() async {
    setState(() => _generando = true);
    try {
      await EstadoAnualService.generarEstadoAnual(widget.firebaseUid);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => EstadoFinancieroAnualScreen(firebaseUid: widget.firebaseUid),
      ));
    } catch (e) {
      _snack('Error al generar: $e');
      if (mounted) setState(() => _generando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          // ── Barra de progreso ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(children: List.generate(3, (i) => Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i <= _paso ? AppTheme.primary : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ))),
          ),
          // ── Botón atrás ──────────────────────────────────────────
          if (_paso > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _irAtras,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Atrás'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
            )
          else
            const SizedBox(height: 8),
          // ── Contenido ────────────────────────────────────────────
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Paso1(
                  tipoIngreso: _tipoIngreso,
                  brutoCtrl: _brutoCtrl,
                  netoCtrl: _netoCtrl,
                  frecuencia: _frecuencia,
                  netoEstimado: _netoEstimado,
                  fmt: _fmt,
                  guardando: _guardandoIncome,
                  onTipoChanged: (v) => setState(() => _tipoIngreso = v),
                  onFrecuenciaChanged: (v) => setState(() => _frecuencia = v),
                  onContinuar: _guardarIncome,
                  onSkip: _irSiguiente,
                ),
                _Paso2(
                  gastosFijos: _gastosFijos,
                  sugerencias: _sugerencias,
                  totalFijos: _totalFijos,
                  fmt: _fmt,
                  guardando: _guardandoGastos,
                  onAgregarGasto: _agregarGastoFijo,
                  onContinuar: _irSiguiente,
                ),
                _Paso3(
                  ingresoNeto: _ingresoNeto,
                  totalFijos: _totalFijos,
                  remanente: _remanente,
                  cantidadGastos: _gastosFijos.length,
                  fmt: _fmt,
                  generando: _generando,
                  onGenerar: _generarEstado,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── PASO 1: INGRESO ───────────────────────────────────────────────────────────

class _Paso1 extends StatefulWidget {
  final String tipoIngreso;
  final TextEditingController brutoCtrl;
  final TextEditingController netoCtrl;
  final String frecuencia;
  final double netoEstimado;
  final NumberFormat fmt;
  final bool guardando;
  final ValueChanged<String> onTipoChanged;
  final ValueChanged<String> onFrecuenciaChanged;
  final VoidCallback onContinuar;
  final VoidCallback onSkip;
  const _Paso1({
    required this.tipoIngreso, required this.brutoCtrl, required this.netoCtrl,
    required this.frecuencia, required this.netoEstimado, required this.fmt,
    required this.guardando, required this.onTipoChanged, required this.onFrecuenciaChanged,
    required this.onContinuar, required this.onSkip,
  });
  @override
  State<_Paso1> createState() => _Paso1State();
}

class _Paso1State extends State<_Paso1> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 1 de 3', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Cuánto ganas al mes?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Tu ingreso neto es la base de todo el sistema. Puedes ajustarlo después.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
        const SizedBox(height: 28),

        // Tipo de ingreso
        const Text('Tipo de ingreso', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          _tipoChip('salario', 'Salario fijo', Icons.badge_outlined),
          const SizedBox(width: 10),
          _tipoChip('informal', 'Independiente', Icons.handshake_outlined),
        ]),
        const SizedBox(height: 20),

        if (widget.tipoIngreso == 'salario') ...[
          _inputLabel('Salario bruto mensual (B/.)'),
          const SizedBox(height: 6),
          _input(widget.brutoCtrl, 'Ej: 1,200.00', onChanged: (_) => setState(() {})),
          if (widget.netoEstimado > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Neto estimado (CSS + Ed. + ISR)',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  Text('B/. ${widget.fmt.format(widget.netoEstimado)}',
                      style: const TextStyle(color: AppTheme.success, fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
          ],
        ] else ...[
          _inputLabel('¿Cuánto recibes neto al mes? (B/.)'),
          const SizedBox(height: 6),
          _input(widget.netoCtrl, 'Ej: 900.00', onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: 20),

        // Frecuencia
        const Text('¿Cada cuánto cobras?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          _frecChip('mensual', 'Mensual'),
          const SizedBox(width: 10),
          _frecChip('quincenal', 'Quincenal'),
        ]),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: widget.guardando ? null : widget.onContinuar,
            child: widget.guardando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Continuar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: widget.onSkip,
            child: const Text('Saltar por ahora', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _tipoChip(String valor, String label, IconData icon) {
    final sel = widget.tipoIngreso == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTipoChanged(valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: sel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.primary : AppTheme.border, width: sel ? 2 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: sel ? AppTheme.primary : AppTheme.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: sel ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget _frecChip(String valor, String label) {
    final sel = widget.frecuencia == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onFrecuenciaChanged(valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.primary : AppTheme.border, width: sel ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            color: sel ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: sel ? FontWeight.w700 : FontWeight.normal, fontSize: 13,
          )),
        ),
      ),
    );
  }

  Widget _inputLabel(String text) => Text(text,
      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600));

  Widget _input(TextEditingController ctrl, String hint, {ValueChanged<String>? onChanged}) =>
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textMuted),
          prefixText: 'B/. ',
          prefixStyle: const TextStyle(color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

// ── PASO 2: GASTOS FIJOS ──────────────────────────────────────────────────────

class _Paso2 extends StatefulWidget {
  final List<Map<String, dynamic>> gastosFijos;
  final List<Map<String, dynamic>> sugerencias;
  final double totalFijos;
  final NumberFormat fmt;
  final bool guardando;
  final Future<void> Function(String nombre, double monto) onAgregarGasto;
  final VoidCallback onContinuar;
  const _Paso2({
    required this.gastosFijos, required this.sugerencias, required this.totalFijos,
    required this.fmt, required this.guardando, required this.onAgregarGasto,
    required this.onContinuar,
  });
  @override
  State<_Paso2> createState() => _Paso2State();
}

class _Paso2State extends State<_Paso2> {
  void _abrirInputMonto(String nombre) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Monto mensual — $nombre',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
          decoration: const InputDecoration(
            prefixText: 'B/. ',
            prefixStyle: TextStyle(color: AppTheme.textSecondary),
            hintText: '0.00',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () async {
              final monto = double.tryParse(ctrl.text);
              if (monto == null || monto <= 0) return;
              Navigator.pop(context);
              await widget.onAgregarGasto(nombre, monto);
            },
            child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(() => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final agregados = widget.gastosFijos.map((g) => g['nombre'] as String).toSet();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 2 de 3', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Qué pagas cada mes?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Estos son tus compromisos fijos. Puedes agregar o editar más después.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
        const SizedBox(height: 24),

        // Chips de sugerencias
        Wrap(spacing: 8, runSpacing: 8, children: widget.sugerencias.map((s) {
          final nombre = s['nombre'] as String;
          final icon = s['icon'] as IconData;
          final yaAgregado = agregados.contains(nombre);
          return GestureDetector(
            onTap: yaAgregado ? null : () => _abrirInputMonto(nombre),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: yaAgregado ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: yaAgregado ? AppTheme.success : AppTheme.border,
                  width: yaAgregado ? 1.5 : 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(yaAgregado ? Icons.check : icon,
                    color: yaAgregado ? AppTheme.success : AppTheme.textSecondary, size: 15),
                const SizedBox(width: 5),
                Text(nombre, style: TextStyle(
                  color: yaAgregado ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 13, fontWeight: yaAgregado ? FontWeight.w600 : FontWeight.normal,
                )),
              ]),
            ),
          );
        }).toList()),

        const SizedBox(height: 16),
        // Agregar otro personalizado
        GestureDetector(
          onTap: () {
            final nombreCtrl = TextEditingController();
            final montoCtrl  = TextEditingController();
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Otro gasto fijo',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: nombreCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(hintText: 'Nombre del gasto',
                        hintStyle: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: montoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(prefixText: 'B/. ',
                        hintText: '0.00', hintStyle: TextStyle(color: AppTheme.textMuted)),
                  ),
                ]),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                    onPressed: () async {
                      final nombre = nombreCtrl.text.trim();
                      final monto = double.tryParse(montoCtrl.text);
                      if (nombre.isEmpty || monto == null || monto <= 0) return;
                      Navigator.pop(context);
                      await widget.onAgregarGasto(nombre, monto);
                    },
                    child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ).whenComplete(() { nombreCtrl.dispose(); montoCtrl.dispose(); });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border, style: BorderStyle.solid),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, color: AppTheme.textMuted, size: 15),
              SizedBox(width: 5),
              Text('Otro...', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ]),
          ),
        ),

        if (widget.gastosFijos.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 8),
          ...widget.gastosFijos.map((g) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.check_circle, color: AppTheme.success, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(g['nombre'] as String,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
              Text('B/. ${widget.fmt.format(g['monto'] as double)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            ]),
          )),
          const Divider(color: AppTheme.border),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total fijos', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            Text('B/. ${widget.fmt.format(widget.totalFijos)}',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ],

        const SizedBox(height: 32),
        if (widget.guardando)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: widget.onContinuar,
              child: Text(
                widget.gastosFijos.isEmpty ? 'Saltar por ahora' : 'Continuar',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── PASO 3: GENERAR ───────────────────────────────────────────────────────────

class _Paso3 extends StatelessWidget {
  final double ingresoNeto;
  final double totalFijos;
  final double remanente;
  final int cantidadGastos;
  final NumberFormat fmt;
  final bool generando;
  final VoidCallback onGenerar;
  const _Paso3({
    required this.ingresoNeto, required this.totalFijos, required this.remanente,
    required this.cantidadGastos, required this.fmt, required this.generando,
    required this.onGenerar,
  });

  @override
  Widget build(BuildContext context) {
    final remColor = remanente >= 0 ? AppTheme.success : AppTheme.danger;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 3 de 3', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('Tu perfil está listo',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Esto es lo que detectamos. Salarying proyectará tus 12 meses automáticamente.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
        const SizedBox(height: 32),

        // Resumen
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: [
            _ResumenRow('Ingreso neto mensual', 'B/. ${fmt.format(ingresoNeto)}', AppTheme.success),
            const Divider(color: AppTheme.border, height: 20),
            _ResumenRow('Compromisos fijos ($cantidadGastos)', '− B/. ${fmt.format(totalFijos)}', AppTheme.danger),
            const Divider(color: AppTheme.border, height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Remanente estimado',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('B/. ${fmt.format(remanente)}',
                  style: TextStyle(color: remColor, fontWeight: FontWeight.w800, fontSize: 22)),
            ]),
          ]),
        ),

        const SizedBox(height: 12),
        if (remanente < 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Tus compromisos superan tu ingreso. Te recomendamos revisar tus gastos fijos.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
              )),
            ]),
          ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: generando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.rocket_launch_outlined, color: Colors.black, size: 20),
            label: Text(
              generando ? 'Generando...' : 'Generar mi Estado Financiero',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: generando ? null : onGenerar,
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('Podrás ajustar todo esto desde tu Perfil Financiero.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _ResumenRow extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  const _ResumenRow(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
    ],
  );
}
