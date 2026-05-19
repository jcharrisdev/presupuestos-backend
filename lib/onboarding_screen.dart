import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/user_profile_service.dart';
import 'services/estado_anual_service.dart';
import 'services/deudas_service.dart';
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

  // ── Paso 1: Ingreso ──────────────────────────────────────────────────
  String _tipoIngreso = 'salario';
  bool _aplicarCss    = true;
  final _brutoCtrl    = TextEditingController();
  final _netoCtrl     = TextEditingController();
  String _frecuencia  = 'mensual';
  bool _guardandoIncome = false;

  // ── Paso 2: Gastos fijos ─────────────────────────────────────────────
  final List<Map<String, dynamic>> _gastosFijos = [];
  bool _guardandoGastos = false;

  // ── Paso 3: Deudas ───────────────────────────────────────────────────
  final List<Map<String, dynamic>> _deudas = [];
  bool _guardandoDeuda = false;

  // ── Paso 4: Generar ──────────────────────────────────────────────────
  bool _generando = false;

  final _fmt = NumberFormat('#,##0.00', 'en_US');

  static const _sugerencias = [
    {'nombre': 'Alquiler',     'icon': Icons.home_outlined,           'tipo': 'esencial'},
    {'nombre': 'Carro',        'icon': Icons.directions_car_outlined,  'tipo': 'esencial'},
    {'nombre': 'Electricidad', 'icon': Icons.bolt_outlined,            'tipo': 'esencial'},
    {'nombre': 'Agua',         'icon': Icons.water_drop_outlined,      'tipo': 'esencial'},
    {'nombre': 'Internet',     'icon': Icons.wifi_outlined,            'tipo': 'esencial'},
    {'nombre': 'Celular',      'icon': Icons.phone_android_outlined,   'tipo': 'esencial'},
    {'nombre': 'Seguro',       'icon': Icons.health_and_safety_outlined,'tipo': 'esencial'},
    {'nombre': 'Alimentación', 'icon': Icons.restaurant_outlined,      'tipo': 'esencial'},
    {'nombre': 'Streaming',    'icon': Icons.tv_outlined,              'tipo': 'no_esencial'},
    {'nombre': 'Gimnasio',     'icon': Icons.fitness_center_outlined,  'tipo': 'no_esencial'},
  ];

  static const _tiposDeuda = [
    {'label': 'Tarjeta',   'valor': 'tarjeta_credito', 'icono': Icons.credit_card,         'hint': '18–36% anual es típico para tarjetas en Panamá.'},
    {'label': 'Préstamo',  'valor': 'prestamo',         'icono': Icons.account_balance,      'hint': '6–18% anual. Busca la TEA en tu contrato.'},
    {'label': 'Auto',      'valor': 'auto',             'icono': Icons.directions_car,       'hint': '4–10% anual. Está en el contrato de financiamiento.'},
    {'label': 'Personal',  'valor': 'personal',         'icono': Icons.person_outline,       'hint': 'Busca la Tasa Efectiva Anual (TEA) en tu estado de cuenta.'},
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    _brutoCtrl.dispose();
    _netoCtrl.dispose();
    super.dispose();
  }

  // ── Cálculos ─────────────────────────────────────────────────────────

  double get _netoEstimado {
    final bruto = double.tryParse(_brutoCtrl.text.replaceAll(',', '')) ?? 0;
    if (bruto <= 0) return 0;
    return _aplicarCss ? bruto * 0.89 : bruto;
  }

  double get _ingresoNeto {
    if (_tipoIngreso == 'salario') return _netoEstimado;
    return double.tryParse(_netoCtrl.text.replaceAll(',', '')) ?? 0;
  }

  double get _totalFijos => _gastosFijos.fold(0.0, (s, g) => s + (g['monto'] as double));
  double get _totalDeudas => _deudas.fold(0.0, (s, d) => s + (d['cuota'] as double));
  double get _remanente   => _ingresoNeto - _totalFijos - _totalDeudas;

  static double _pmt(double principal, double tasaAnual, int plazoMeses) {
    if (principal <= 0 || plazoMeses <= 0) return 0;
    if (tasaAnual <= 0) return principal / plazoMeses;
    final r = tasaAnual / 100 / 12;
    final factor = math.pow(1 + r, plazoMeses);
    return principal * r * factor / (factor - 1);
  }

  // ── Navegación ───────────────────────────────────────────────────────

  void _irSiguiente() {
    if (_paso < 3) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _paso++);
    }
  }

  void _irAtras() {
    if (_paso > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _paso--);
    }
  }

  // ── Acciones backend ─────────────────────────────────────────────────

  Future<void> _guardarIncome() async {
    final neto = _ingresoNeto;
    if (neto <= 0) { _snack('Ingresa un monto válido'); return; }
    setState(() => _guardandoIncome = true);
    try {
      final bruto = _tipoIngreso == 'salario'
          ? (double.tryParse(_brutoCtrl.text.replaceAll(',', '')) ?? neto)
          : neto;
      await UserProfileService.upsertIncome(widget.firebaseUid, {
        'tipo_ingreso': _tipoIngreso,
        'ingreso_bruto_mensual': bruto,
        'ingreso_neto_mensual':  neto,
        'calcular_automatico':   (_tipoIngreso == 'salario' && _aplicarCss) ? 1 : 0,
        'frecuencia_cobro':      _frecuencia,
      });
      _irSiguiente();
    } catch (e) {
      _snack('Error al guardar ingreso');
    }
    if (mounted) setState(() => _guardandoIncome = false);
  }

  Future<void> _agregarGastoFijo(String nombre, double monto, String tipo) async {
    setState(() => _guardandoGastos = true);
    try {
      await UserProfileService.crearGastoFijo(widget.firebaseUid, {
        'descripcion': nombre,
        'monto_mensual': monto,
        'tipo': 'fijo',
        'clasificacion': tipo,
        'frecuencia': 'fijo',
        'activo': 1,
      });
      setState(() => _gastosFijos.add({'nombre': nombre, 'monto': monto, 'tipo': tipo}));
    } catch (_) {
      _snack('Error al guardar gasto');
    }
    if (mounted) setState(() => _guardandoGastos = false);
  }

  Future<void> _agregarDeuda(
      String nombre, String tipo, double montoTotal, double tasaAnual, int plazoMeses) async {
    setState(() => _guardandoDeuda = true);
    final cuota = _pmt(montoTotal, tasaAnual, plazoMeses);
    try {
      await DeudasService.crear({
        'firebase_uid':    widget.firebaseUid,
        'nombre':          nombre,
        'tipo':            tipo,
        'monto_total':     montoTotal,
        'monto_pendiente': montoTotal,
        'tasa_interes':    tasaAnual,
        'pago_minimo':     double.parse(cuota.toStringAsFixed(2)),
      });
      setState(() => _deudas.add({
        'nombre': nombre,
        'tipo':   tipo,
        'monto':  montoTotal,
        'tasa':   tasaAnual,
        'plazo':  plazoMeses,
        'cuota':  cuota,
      }));
    } catch (_) {
      _snack('Error al guardar deuda');
    }
    if (mounted) setState(() => _guardandoDeuda = false);
  }

  Future<void> _generarEstado() async {
    setState(() => _generando = true);
    try {
      await EstadoAnualService.generarEstadoAnual(widget.firebaseUid);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => EstadoFinancieroAnualScreen(firebaseUid: widget.firebaseUid),
      ));
    } catch (_) {
      _snack('Error al generar el estado. Intenta de nuevo.');
      if (mounted) setState(() => _generando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          // Barra de progreso (4 pasos)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(children: List.generate(4, (i) => Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i <= _paso ? AppTheme.primary : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ))),
          ),
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
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Paso1Income(
                  tipoIngreso:    _tipoIngreso,
                  aplicarCss:     _aplicarCss,
                  brutoCtrl:      _brutoCtrl,
                  netoCtrl:       _netoCtrl,
                  frecuencia:     _frecuencia,
                  netoEstimado:   _netoEstimado,
                  fmt:            _fmt,
                  guardando:      _guardandoIncome,
                  onTipoChanged:       (v) => setState(() => _tipoIngreso = v),
                  onCssChanged:        (v) => setState(() => _aplicarCss = v),
                  onFrecuenciaChanged: (v) => setState(() => _frecuencia = v),
                  onContinuar: _guardarIncome,
                  onSkip:      _irSiguiente,
                ),
                _Paso2Gastos(
                  gastosFijos:     _gastosFijos,
                  sugerencias:     _sugerencias,
                  totalFijos:      _totalFijos,
                  fmt:             _fmt,
                  guardando:       _guardandoGastos,
                  onAgregarGasto:  _agregarGastoFijo,
                  onContinuar:     _irSiguiente,
                ),
                _Paso3Deudas(
                  deudas:          _deudas,
                  tiposDeuda:      _tiposDeuda,
                  totalDeudas:     _totalDeudas,
                  fmt:             _fmt,
                  guardando:       _guardandoDeuda,
                  pmt:             _pmt,
                  onAgregarDeuda:  _agregarDeuda,
                  onContinuar:     _irSiguiente,
                ),
                _Paso4Resumen(
                  ingresoNeto:   _ingresoNeto,
                  totalFijos:    _totalFijos,
                  totalDeudas:   _totalDeudas,
                  remanente:     _remanente,
                  cantGastos:    _gastosFijos.length,
                  cantDeudas:    _deudas.length,
                  fmt:           _fmt,
                  generando:     _generando,
                  onGenerar:     _generarEstado,
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

class _Paso1Income extends StatefulWidget {
  final String tipoIngreso;
  final bool aplicarCss;
  final TextEditingController brutoCtrl;
  final TextEditingController netoCtrl;
  final String frecuencia;
  final double netoEstimado;
  final NumberFormat fmt;
  final bool guardando;
  final ValueChanged<String> onTipoChanged;
  final ValueChanged<bool>   onCssChanged;
  final ValueChanged<String> onFrecuenciaChanged;
  final VoidCallback onContinuar;
  final VoidCallback onSkip;
  const _Paso1Income({
    required this.tipoIngreso, required this.aplicarCss,
    required this.brutoCtrl, required this.netoCtrl,
    required this.frecuencia, required this.netoEstimado,
    required this.fmt, required this.guardando,
    required this.onTipoChanged, required this.onCssChanged,
    required this.onFrecuenciaChanged,
    required this.onContinuar, required this.onSkip,
  });
  @override
  State<_Paso1Income> createState() => _Paso1IncomeState();
}

class _Paso1IncomeState extends State<_Paso1Income> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 1 de 4', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Cuánto ganas?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Tu ingreso neto es la base de todo. Define cuánto recibes realmente cada mes.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),

        // Tipo de ingreso
        _Label('Tipo de ingreso'),
        const SizedBox(height: 8),
        Row(children: [
          _TipoChip('salario',  'Salario fijo',    Icons.badge_outlined,     widget.tipoIngreso, widget.onTipoChanged),
          const SizedBox(width: 10),
          _TipoChip('informal', 'Independiente',   Icons.handshake_outlined, widget.tipoIngreso, widget.onTipoChanged),
        ]),
        const SizedBox(height: 6),
        _InfoBox(widget.tipoIngreso == 'salario'
            ? 'Empleado en planilla — tu empleador descuenta CSS, educativo e ISR antes de pagarte.'
            : 'Freelance, negocio propio o ingresos variables — ingresa tu promedio mensual neto.'),
        const SizedBox(height: 20),

        if (widget.tipoIngreso == 'salario') ...[
          _Label('Salario bruto mensual (B/.)'),
          const SizedBox(height: 6),
          _Input(widget.brutoCtrl, 'Ej: 1,200.00', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          // Toggle CSS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_outlined, color: AppTheme.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Aplicar CSS + Educativo (11%)',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const Text('Descuentos de nómina obligatorios en Panamá',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ])),
              Switch(
                value: widget.aplicarCss,
                activeColor: AppTheme.primary,
                onChanged: widget.onCssChanged,
              ),
            ]),
          ),
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
                  Text(
                    widget.aplicarCss ? 'Neto estimado (con descuentos)' : 'Neto completo (sin descuentos)',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  Text('B/. ${widget.fmt.format(widget.netoEstimado)}',
                      style: const TextStyle(color: AppTheme.success, fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
          ],
        ] else ...[
          _Label('¿Cuánto recibes promedio al mes? (B/.)'),
          const SizedBox(height: 6),
          _Input(widget.netoCtrl, 'Ej: 900.00', onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: 20),

        // Frecuencia
        _Label('¿Cada cuánto cobras?'),
        const SizedBox(height: 8),
        Row(children: [
          _FrecChip('mensual',   'Mensual',   widget.frecuencia, widget.onFrecuenciaChanged),
          const SizedBox(width: 10),
          _FrecChip('quincenal', 'Quincenal', widget.frecuencia, widget.onFrecuenciaChanged),
        ]),
        const SizedBox(height: 4),
        Text(
          widget.frecuencia == 'quincenal'
              ? 'Recibirás dos pagos al mes: B/. ${widget.fmt.format(widget.netoEstimado > 0 ? widget.netoEstimado / 2 : (double.tryParse(widget.netoCtrl.text) ?? 0) / 2)} c/u'
              : 'Un pago al mes.',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 32),

        _BtnPrimary(
          label: 'Continuar',
          loading: widget.guardando,
          onPressed: widget.onContinuar,
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
}

// ── PASO 2: GASTOS FIJOS ──────────────────────────────────────────────────────

class _Paso2Gastos extends StatefulWidget {
  final List<Map<String, dynamic>> gastosFijos;
  final List<Map<String, dynamic>> sugerencias;
  final double totalFijos;
  final NumberFormat fmt;
  final bool guardando;
  final Future<void> Function(String nombre, double monto, String tipo) onAgregarGasto;
  final VoidCallback onContinuar;
  const _Paso2Gastos({
    required this.gastosFijos, required this.sugerencias, required this.totalFijos,
    required this.fmt, required this.guardando,
    required this.onAgregarGasto, required this.onContinuar,
  });
  @override
  State<_Paso2Gastos> createState() => _Paso2GastosState();
}

class _Paso2GastosState extends State<_Paso2Gastos> {
  void _abrirFormGasto(String nombre, String tipoPre) {
    final montoCtrl  = TextEditingController();
    String tipo = tipoPre;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('$nombre — monto mensual',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: montoCtrl,
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
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Categoría', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _TipoGastoChip('Esencial',    'esencial',    tipo, (v) => setDlg(() => tipo = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Opcional',    'no_esencial', tipo, (v) => setDlg(() => tipo = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Ahorro',      'ahorro',      tipo, (v) => setDlg(() => tipo = v)),
            ]),
            const SizedBox(height: 8),
            _InfoBox(_tipoGastoExplicacion(tipo), small: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () async {
                final monto = double.tryParse(montoCtrl.text.replaceAll(',', ''));
                if (monto == null || monto <= 0) return;
                Navigator.pop(ctx);
                await widget.onAgregarGasto(nombre, monto, tipo);
              },
              child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).whenComplete(() => montoCtrl.dispose());
  }

  void _abrirFormPersonalizado() {
    final nombreCtrl = TextEditingController();
    final montoCtrl  = TextEditingController();
    String tipo = 'esencial';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Otro gasto fijo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Nombre del gasto',
                hintStyle: TextStyle(color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                prefixText: 'B/. ',
                hintText: '0.00',
                hintStyle: TextStyle(color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _TipoGastoChip('Esencial',  'esencial',    tipo, (v) => setDlg(() => tipo = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Opcional',  'no_esencial', tipo, (v) => setDlg(() => tipo = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Ahorro',    'ahorro',      tipo, (v) => setDlg(() => tipo = v)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final monto  = double.tryParse(montoCtrl.text.replaceAll(',', ''));
                if (nombre.isEmpty || monto == null || monto <= 0) return;
                Navigator.pop(ctx);
                await widget.onAgregarGasto(nombre, monto, tipo);
              },
              child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).whenComplete(() { nombreCtrl.dispose(); montoCtrl.dispose(); });
  }

  static String _tipoGastoExplicacion(String tipo) {
    switch (tipo) {
      case 'esencial':    return 'No puedes eliminarlo sin impactar tu vida diaria: alquiler, servicios, alimentación.';
      case 'no_esencial': return 'Puedes reducirlo si aprietas: streaming, salidas, suscripciones.';
      case 'ahorro':      return 'Dinero que reservas cada mes para una meta o fondo de emergencia.';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final agregados = widget.gastosFijos.map((g) => g['nombre'] as String).toSet();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 2 de 4', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Qué pagas cada mes?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Los gastos fijos son compromisos que tienes todos los meses sin importar lo que pase.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 10),
        _InfoBox('Las deudas (tarjetas, préstamos) las agregarás en el siguiente paso. Aquí solo servicios y compromisos del hogar.'),
        const SizedBox(height: 20),

        const Text('Toca los que apliquen:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ...widget.sugerencias.map((s) {
            final nombre = s['nombre'] as String;
            final icon   = s['icon'] as IconData;
            final tipo   = s['tipo'] as String;
            final ya     = agregados.contains(nombre);
            return GestureDetector(
              onTap: ya ? null : () => _abrirFormGasto(nombre, tipo),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ya ? AppTheme.success.withValues(alpha: 0.12) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ya ? AppTheme.success : AppTheme.border, width: ya ? 1.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ya ? Icons.check : icon,
                      color: ya ? AppTheme.success : AppTheme.textSecondary, size: 14),
                  const SizedBox(width: 5),
                  Text(nombre, style: TextStyle(
                    color: ya ? AppTheme.success : AppTheme.textSecondary,
                    fontSize: 13, fontWeight: ya ? FontWeight.w600 : FontWeight.normal,
                  )),
                ]),
              ),
            );
          }),
          GestureDetector(
            onTap: _abrirFormPersonalizado,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: AppTheme.textMuted, size: 14),
                SizedBox(width: 5),
                Text('Otro...', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ]),
            ),
          ),
        ]),

        if (widget.gastosFijos.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: AppTheme.border),
          ...widget.gastosFijos.map((g) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.check_circle, color: AppTheme.success, size: 15),
              const SizedBox(width: 8),
              Expanded(child: Text(g['nombre'] as String,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
              _TipoBadge(g['tipo'] as String),
              const SizedBox(width: 8),
              Text('B/. ${widget.fmt.format(g['monto'] as double)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          )),
          const Divider(color: AppTheme.border),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total fijos', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            Text('B/. ${widget.fmt.format(widget.totalFijos)}',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
        ],

        const SizedBox(height: 32),
        if (widget.guardando)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else
          _BtnPrimary(
            label: widget.gastosFijos.isEmpty ? 'Saltar por ahora' : 'Continuar',
            onPressed: widget.onContinuar,
          ),
      ]),
    );
  }
}

// ── PASO 3: DEUDAS ────────────────────────────────────────────────────────────

class _Paso3Deudas extends StatefulWidget {
  final List<Map<String, dynamic>> deudas;
  final List<Map<String, dynamic>> tiposDeuda;
  final double totalDeudas;
  final NumberFormat fmt;
  final bool guardando;
  final double Function(double, double, int) pmt;
  final Future<void> Function(String, String, double, double, int) onAgregarDeuda;
  final VoidCallback onContinuar;
  const _Paso3Deudas({
    required this.deudas, required this.tiposDeuda, required this.totalDeudas,
    required this.fmt, required this.guardando, required this.pmt,
    required this.onAgregarDeuda, required this.onContinuar,
  });
  @override
  State<_Paso3Deudas> createState() => _Paso3DeudasState();
}

class _Paso3DeudasState extends State<_Paso3Deudas> {
  void _abrirFormDeuda() {
    final nombreCtrl = TextEditingController();
    final montoCtrl  = TextEditingController();
    final tasaCtrl   = TextEditingController();
    final plazoCtrl  = TextEditingController();
    String tipo = 'tarjeta_credito';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final principal = double.tryParse(montoCtrl.text.replaceAll(',', '')) ?? 0;
          final tasa      = double.tryParse(tasaCtrl.text) ?? 0;
          final plazo     = int.tryParse(plazoCtrl.text) ?? 0;
          final cuota     = widget.pmt(principal, tasa, plazo);

          final hint = widget.tiposDeuda
              .firstWhere((t) => t['valor'] == tipo, orElse: () => widget.tiposDeuda.first)['hint'] as String;

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Agregar deuda',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Tipo de deuda
                Wrap(spacing: 6, runSpacing: 6, children: widget.tiposDeuda.map((t) {
                  final sel = tipo == t['valor'] as String;
                  return GestureDetector(
                    onTap: () => setDlg(() => tipo = t['valor'] as String),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? AppTheme.primary : AppTheme.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(t['icono'] as IconData, size: 13, color: sel ? AppTheme.primary : AppTheme.textSecondary),
                        const SizedBox(width: 5),
                        Text(t['label'] as String, style: TextStyle(
                          fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                          color: sel ? AppTheme.primary : AppTheme.textSecondary,
                        )),
                      ]),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 6),
                _InfoBox(hint, small: true),
                const SizedBox(height: 12),

                // Nombre
                TextField(
                  controller: nombreCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: _deco('Nombre de la deuda (ej: Tarjeta BAC)'),
                ),
                const SizedBox(height: 10),

                // Monto total
                TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  onChanged: (_) => setDlg(() {}),
                  decoration: _deco('Monto total adeudado (B/.)'),
                ),
                const SizedBox(height: 10),

                // Tasa anual
                TextField(
                  controller: tasaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  onChanged: (_) => setDlg(() {}),
                  decoration: _deco('Tasa de interés anual (%)'),
                ),
                const SizedBox(height: 10),

                // Plazo
                TextField(
                  controller: plazoCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  onChanged: (_) => setDlg(() {}),
                  decoration: _deco('Plazo en meses (ej: 36)'),
                ),

                // Cuota calculada
                if (cuota > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Cuota mensual:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        Text('B/. ${cuota.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      if (plazo > 0) ...[
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Total a pagar:', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          Text('B/. ${(cuota * plazo).toStringAsFixed(2)}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        ]),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Total intereses:', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          Text('B/. ${(cuota * plazo - principal).toStringAsFixed(2)}',
                              style: const TextStyle(color: AppTheme.warning, fontSize: 11)),
                        ]),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () async {
                  final nombre = nombreCtrl.text.trim();
                  if (nombre.isEmpty || principal <= 0 || plazo <= 0) return;
                  Navigator.pop(ctx);
                  await widget.onAgregarDeuda(nombre, tipo, principal, tasa, plazo);
                },
                child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() { nombreCtrl.dispose(); montoCtrl.dispose(); tasaCtrl.dispose(); plazoCtrl.dispose(); });
  }

  static InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 3 de 4', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Tienes deudas?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Tarjetas de crédito, préstamos, letras. Agrégalos para ver tu disponible real.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 10),
        _InfoBox('Solo necesitas: monto total que debes, tasa anual de interés y cuántos meses faltan. La app calcula tu cuota mensual con la fórmula financiera estándar.'),
        const SizedBox(height: 24),

        GestureDetector(
          onTap: _abrirFormDeuda,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text('Agregar deuda / tarjeta',
                  style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14)),
            ]),
          ),
        ),

        if (widget.deudas.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: AppTheme.border),
          ...widget.deudas.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.credit_card_outlined, color: AppTheme.danger, size: 15),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['nombre'] as String,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${(d['tasa'] as double).toStringAsFixed(1)}% anual · ${d['plazo']} meses',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ])),
              Text('−B/. ${(d['cuota'] as double).toStringAsFixed(2)}/mes',
                  style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          )),
          const Divider(color: AppTheme.border),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total cuotas/mes', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            Text('B/. ${widget.fmt.format(widget.totalDeudas)}',
                style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
        ],

        const SizedBox(height: 32),
        if (widget.guardando)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else
          _BtnPrimary(
            label: widget.deudas.isEmpty ? 'No tengo deudas, continuar' : 'Continuar',
            onPressed: widget.onContinuar,
          ),
      ]),
    );
  }
}

// ── PASO 4: RESUMEN ───────────────────────────────────────────────────────────

class _Paso4Resumen extends StatelessWidget {
  final double ingresoNeto;
  final double totalFijos;
  final double totalDeudas;
  final double remanente;
  final int cantGastos;
  final int cantDeudas;
  final NumberFormat fmt;
  final bool generando;
  final VoidCallback onGenerar;
  const _Paso4Resumen({
    required this.ingresoNeto, required this.totalFijos, required this.totalDeudas,
    required this.remanente, required this.cantGastos, required this.cantDeudas,
    required this.fmt, required this.generando, required this.onGenerar,
  });

  @override
  Widget build(BuildContext context) {
    final remColor = remanente >= 0 ? AppTheme.success : AppTheme.danger;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 4 de 4', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('Tu perfil financiero',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Resumen de lo que configuraste. Salarying proyectará tus 12 meses.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: [
            _ResRow('Ingreso neto mensual',
                'B/. ${fmt.format(ingresoNeto)}', AppTheme.success),
            const Divider(color: AppTheme.border, height: 20),
            _ResRow('Gastos fijos ($cantGastos)',
                '− B/. ${fmt.format(totalFijos)}', AppTheme.textSecondary),
            if (cantDeudas > 0) ...[
              const SizedBox(height: 6),
              _ResRow('Cuotas de deudas ($cantDeudas)',
                  '− B/. ${fmt.format(totalDeudas)}', AppTheme.danger),
            ],
            const Divider(color: AppTheme.border, height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Disponible estimado',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('B/. ${fmt.format(remanente)}',
                  style: TextStyle(color: remColor, fontWeight: FontWeight.w800, fontSize: 24)),
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
                'Tus compromisos superan tu ingreso. Te recomendamos revisar tus gastos fijos y deudas.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
              )),
            ]),
          )
        else if (remanente < ingresoNeto * 0.15 && ingresoNeto > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.info, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Tu disponible es menor al 15% del ingreso. Intenta reducir gastos opcionales.',
                style: TextStyle(color: AppTheme.info, fontSize: 12, height: 1.4),
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
        const SizedBox(height: 14),
        const Center(
          child: Text('Puedes ajustar todo desde tu Perfil Financiero en cualquier momento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _ResRow extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  const _ResRow(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
    ],
  );
}

// ── SHARED WIDGETS ────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final String text;
  final bool small;
  const _InfoBox(this.text, {this.small = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.lightbulb_outline, color: AppTheme.textMuted, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: small ? 11 : 12,
        height: 1.4,
      ))),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600));
}

class _Input extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<String>? onChanged;
  const _Input(this.ctrl, this.hint, {this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
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

class _BtnPrimary extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  const _BtnPrimary({required this.label, this.loading = false, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
    ),
  );
}

class _TipoChip extends StatelessWidget {
  final String valor, label;
  final IconData icon;
  final String selected;
  final ValueChanged<String> onTap;
  const _TipoChip(this.valor, this.label, this.icon, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(valor),
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
            Text(label, style: TextStyle(
              color: sel ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal, fontSize: 13,
            )),
          ]),
        ),
      ),
    );
  }
}

class _FrecChip extends StatelessWidget {
  final String valor, label, selected;
  final ValueChanged<String> onTap;
  const _FrecChip(this.valor, this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(valor),
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
}

class _TipoGastoChip extends StatelessWidget {
  final String label, valor, selected;
  final ValueChanged<String> onTap;
  const _TipoGastoChip(this.label, this.valor, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == valor;
    return GestureDetector(
      onTap: () => onTap(valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          color: sel ? AppTheme.primary : AppTheme.textSecondary,
          fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
        )),
      ),
    );
  }
}

class _TipoBadge extends StatelessWidget {
  final String tipo;
  const _TipoBadge(this.tipo);
  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (tipo) {
      case 'esencial':    color = AppTheme.success; label = 'esencial'; break;
      case 'no_esencial': color = AppTheme.warning;  label = 'opcional'; break;
      case 'ahorro':      color = AppTheme.info;     label = 'ahorro';   break;
      default:            color = AppTheme.textMuted; label = tipo;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
