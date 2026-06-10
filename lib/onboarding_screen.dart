import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/user_profile_service.dart';
import 'services/estado_anual_service.dart';
import 'services/deudas_service.dart';
import 'services/gastos_variables_service.dart';

class OnboardingScreen extends StatefulWidget {
  final String firebaseUid;
  final VoidCallback? onCompleted;
  const OnboardingScreen({super.key, required this.firebaseUid, this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _paso = 0;

  // ── Paso 1: Ingreso ──────────────────────────────────────────────────
  String _tipoIngreso = 'informal';
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

  // ── Paso 4: Gastos variables estimados ───────────────────────────────
  // monto por índice de categoría (0-7), modificable por el usuario
  final Map<int, double> _variableMontos = {0:300,1:100,2:80,3:60,4:50,5:40,6:30,7:50};
  final Set<int> _variablesActivas = {0,1,2,3,4,5,6,7};
  bool _guardandoVariables = false;

  static const _categoriasVariable = [
    {'nombre': 'Supermercado',        'categoria': 'alimentacion', 'icon': Icons.shopping_cart_outlined},
    {'nombre': 'Restaurantes',        'categoria': 'alimentacion', 'icon': Icons.restaurant_outlined},
    {'nombre': 'Gasolina / transporte','categoria': 'transporte',  'icon': Icons.local_gas_station_outlined},
    {'nombre': 'Entretenimiento',     'categoria': 'entretenimiento','icon': Icons.movie_outlined},
    {'nombre': 'Ropa / personal',     'categoria': 'personal',     'icon': Icons.checkroom_outlined},
    {'nombre': 'Salud / farmacia',    'categoria': 'salud',        'icon': Icons.local_pharmacy_outlined},
    {'nombre': 'Educación',           'categoria': 'educacion',    'icon': Icons.school_outlined},
    {'nombre': 'Otras compras',       'categoria': 'otro',         'icon': Icons.shopping_bag_outlined},
  ];

  // ── Paso 5: Generar ──────────────────────────────────────────────────
  bool _generando = false;

  final _fmt = NumberFormat('#,##0.00', 'en_US');

  // tipoBackend = ENUM válido en user_gastos_fijos
  // clasificacionBackend = ENUM('esencial','importante','flexible')
  static const _sugerencias = [
    {'nombre': 'Alquiler',     'icon': Icons.home_outlined,            'tipoBackend': 'vivienda',     'clasificacion': 'esencial'},
    {'nombre': 'Carro',        'icon': Icons.directions_car_outlined,  'tipoBackend': 'transporte',   'clasificacion': 'esencial'},
    {'nombre': 'Electricidad', 'icon': Icons.bolt_outlined,            'tipoBackend': 'servicios',    'clasificacion': 'esencial'},
    {'nombre': 'Agua',         'icon': Icons.water_drop_outlined,      'tipoBackend': 'servicios',    'clasificacion': 'esencial'},
    {'nombre': 'Internet',     'icon': Icons.wifi_outlined,            'tipoBackend': 'servicios',    'clasificacion': 'esencial'},
    {'nombre': 'Celular',      'icon': Icons.phone_android_outlined,   'tipoBackend': 'servicios',    'clasificacion': 'esencial'},
    {'nombre': 'Seguro',       'icon': Icons.health_and_safety_outlined,'tipoBackend': 'salud',       'clasificacion': 'esencial'},
    {'nombre': 'Alimentación', 'icon': Icons.restaurant_outlined,      'tipoBackend': 'alimentacion', 'clasificacion': 'esencial'},
    {'nombre': 'Streaming',    'icon': Icons.tv_outlined,              'tipoBackend': 'otro',         'clasificacion': 'flexible'},
    {'nombre': 'Gimnasio',     'icon': Icons.fitness_center_outlined,  'tipoBackend': 'salud',        'clasificacion': 'flexible'},
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

  double get _totalFijos     => _gastosFijos.fold(0.0, (s, g) => s + (g['monto'] as double));
  double get _totalDeudas    => _deudas.fold(0.0, (s, d) => s + (d['cuota'] as double));
  double get _totalVariables => _variablesActivas.fold(0.0,
      (s, i) => s + (_variableMontos[i] ?? 0));
  double get _remanente => _ingresoNeto - _totalFijos - _totalDeudas - _totalVariables;

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

  // Mapea la clasificación UI a ENUM válido en user_gastos_fijos
  static String _clasificacionDB(String uiClasificacion) {
    switch (uiClasificacion) {
      case 'esencial':    return 'esencial';
      case 'flexible':    return 'flexible';
      default:            return 'importante';
    }
  }

  Future<void> _agregarGastoFijo(String nombre, double monto,
      {String tipoBackend = 'otro', String clasificacion = 'esencial'}) async {
    setState(() => _guardandoGastos = true);
    try {
      await UserProfileService.crearGastoFijo(widget.firebaseUid, {
        'descripcion':  nombre,
        'monto_mensual': monto,
        'tipo':          tipoBackend,
        'clasificacion': _clasificacionDB(clasificacion),
        'frecuencia':   'fijo',
        'activo':        1,
      });
      setState(() => _gastosFijos.add({
        'nombre': nombre,
        'monto':  monto,
        'clasificacion': clasificacion,
      }));
    } catch (e) {
      _snack('Error al guardar: $e');
    }
    if (mounted) setState(() => _guardandoGastos = false);
  }

  Future<void> _importarCsvBulk(List<Map<String, dynamic>> gastos) async {
    setState(() => _guardandoGastos = true);
    try {
      await UserProfileService.crearGastosFijosBulk(widget.firebaseUid, gastos);
      setState(() {
        for (final g in gastos) {
          _gastosFijos.add({
            'nombre':        g['descripcion'] as String,
            'monto':         (g['monto_mensual'] as num).toDouble(),
            'clasificacion': g['clasificacion'] as String? ?? 'esencial',
          });
        }
      });
      _snack('${gastos.length} gastos importados correctamente');
    } catch (e) {
      _snack('Error al importar: $e');
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

  Future<void> _guardarVariables() async {
    setState(() => _guardandoVariables = true);
    final lista = _variablesActivas
        .where((i) => (_variableMontos[i] ?? 0) > 0)
        .map((i) => {
              'nombre':         _categoriasVariable[i]['nombre'] as String,
              'categoria':      _categoriasVariable[i]['categoria'] as String,
              'monto_estimado': _variableMontos[i] ?? 0,
            })
        .toList();
    try {
      if (lista.isNotEmpty) {
        await GastosVariablesService.crearBulk(widget.firebaseUid, lista);
      }
      _irSiguiente();
    } catch (_) {
      _snack('No pudimos guardar algunos gastos estimados. Puedes agregarlos desde tu Perfil Financiero después.');
      _irSiguiente();
    }
    if (mounted) setState(() => _guardandoVariables = false);
  }

  Future<void> _generarEstado() async {
    setState(() => _generando = true);
    try {
      await EstadoAnualService.generarEstadoAnual(widget.firebaseUid);
      if (!mounted) return;
      Navigator.pop(context);           // pop primero
      widget.onCompleted?.call();       // callback después del pop
    } catch (e) {
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
          // Barra de progreso (5 pasos)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(children: List.generate(5, (i) => Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
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
                ),
                _Paso2Gastos(
                  gastosFijos:      _gastosFijos,
                  sugerencias:      _sugerencias,
                  totalFijos:       _totalFijos,
                  fmt:              _fmt,
                  guardando:        _guardandoGastos,
                  onAgregarGasto:   _agregarGastoFijo,
                  onImportarBulk:   _importarCsvBulk,
                  onContinuar:      _irSiguiente,
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
                _Paso4Variables(
                  montos:          _variableMontos,
                  activas:         _variablesActivas,
                  categorias:      _categoriasVariable,
                  totalVariables:  _totalVariables,
                  guardando:       _guardandoVariables,
                  fmt:             _fmt,
                  onToggle:        (i, v) => setState(() => v ? _variablesActivas.add(i) : _variablesActivas.remove(i)),
                  onMontoChanged:  (i, v) => setState(() => _variableMontos[i] = v),
                  onContinuar:     _guardarVariables,
                ),
                _Paso5Resumen(
                  ingresoNeto:   _ingresoNeto,
                  totalFijos:    _totalFijos,
                  totalDeudas:   _totalDeudas,
                  totalVariables:_totalVariables,
                  remanente:     _remanente,
                  cantGastos:    _gastosFijos.length,
                  cantDeudas:    _deudas.length,
                  cantVariables: _variablesActivas.length,
                  fmt:           _fmt,
                  generando:     _generando,
                  onGenerar:     _generarEstado,
                  onIrAPaso1:    () => _pageCtrl.animateToPage(0,
                      duration: const Duration(milliseconds: 350), curve: Curves.easeInOut),
                  onIrAGastos:   () => _pageCtrl.animateToPage(1,
                      duration: const Duration(milliseconds: 350), curve: Curves.easeInOut),
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
  const _Paso1Income({
    required this.tipoIngreso, required this.aplicarCss,
    required this.brutoCtrl, required this.netoCtrl,
    required this.frecuencia, required this.netoEstimado,
    required this.fmt, required this.guardando,
    required this.onTipoChanged, required this.onCssChanged,
    required this.onFrecuenciaChanged,
    required this.onContinuar,
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
        const Text('¿Cuánto recibes al mes?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Salario, negocio, freelance, alquiler — cualquier ingreso cuenta. Define cuánto recibes realmente.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),

        // Tipo de ingreso
        _Label('¿Cómo recibes tu ingreso?'),
        const SizedBox(height: 8),
        Row(children: [
          _TipoChip('informal', 'Ingreso propio',  Icons.handshake_outlined, widget.tipoIngreso, widget.onTipoChanged),
          const SizedBox(width: 10),
          _TipoChip('salario',  'Empleo formal',   Icons.badge_outlined,     widget.tipoIngreso, widget.onTipoChanged),
        ]),
        const SizedBox(height: 6),
        _InfoBox(widget.tipoIngreso == 'salario'
            ? 'Empleado en planilla — tu empleador descuenta CSS, educativo e ISR antes de pagarte.'
            : 'Negocio, freelance, ventas, alquiler, remesas u otro ingreso — ingresa tu promedio mensual.'),
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
                // Q2 — fecha de vigencia + camino manual
                const SizedBox(height: 4),
                Text(widget.aplicarCss
                        ? 'Tasas estimadas 2025 · Verifica con tu empleador. ¿Conoces tu neto exacto? Apaga esto e ingresa arriba el monto que te llega a la mano.'
                        : 'Estás ingresando tu neto exacto: escribe arriba el monto que te llega a la mano (sin descuentos automáticos).',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontStyle: FontStyle.italic, height: 1.3)),
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
        const Center(
          child: Text(
            'Necesitamos saber cuánto recibes para mostrarte tu panorama financiero. Puedes ajustarlo después.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
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
  final Future<void> Function(String nombre, double monto, {String tipoBackend, String clasificacion}) onAgregarGasto;
  final Future<void> Function(List<Map<String, dynamic>> gastos) onImportarBulk;
  final VoidCallback onContinuar;
  const _Paso2Gastos({
    required this.gastosFijos, required this.sugerencias, required this.totalFijos,
    required this.fmt, required this.guardando,
    required this.onAgregarGasto, required this.onImportarBulk, required this.onContinuar,
  });
  @override
  State<_Paso2Gastos> createState() => _Paso2GastosState();
}

class _Paso2GastosState extends State<_Paso2Gastos> {
  bool _compartidos = false;

  // ── CSV import ──────────────────────────────────────────────────────

  void _descargarPlantilla() {
    const contenido =
        'Descripcion,Monto\n'
        'Alquiler,500\n'
        'Electricidad,80\n'
        'Internet,45\n'
        'Celular,30\n';
    final bytes = utf8.encode(contenido);
    final blob = html.Blob([bytes], 'text/csv');
    final url  = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'plantilla_gastos.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _importarCsv() {
    final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
    input.click();
    input.onChange.listen((_) {
      final file = input.files?.first;
      if (file == null) return;
      if (!file.name.toLowerCase().endsWith('.csv')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Solo se aceptan archivos .csv — exporta tu Excel como CSV primero.'),
        ));
        return;
      }
      final reader = html.FileReader();
      reader.readAsText(file);
      reader.onLoad.listen((_) => _mostrarRevision(reader.result as String));
    });
  }

  static List<String> _splitLineCsv(String line) {
    final result = <String>[];
    var inQuotes = false;
    final current = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(c);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  void _mostrarRevision(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim().split('\n');
    if (lines.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El archivo no tiene datos. Usa la plantilla.')));
      return;
    }
    final rows = <Map<String, dynamic>>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final cols = _splitLineCsv(line);
      if (cols.length < 2) continue;
      final desc  = cols[0].replaceAll('"', '').trim();
      final monto = double.tryParse(cols[1].replaceAll('"', '').replaceAll(',', '.').trim());
      if (desc.isEmpty || monto == null || monto <= 0) continue;
      rows.add({'descripcion': desc, 'monto_mensual': monto, 'clasificacion': 'esencial'});
    }
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron filas válidas en el archivo.')));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => _RevisionCsvDialog(
        rows: rows,
        onConfirmar: (gastos) async {
          Navigator.pop(context);
          await widget.onImportarBulk(gastos);
        },
      ),
    );
  }

  // Chips usan valores DB-válidos para clasificacion ENUM('esencial','importante','flexible')
  static String _explicacion(String clasificacion) {
    switch (clasificacion) {
      case 'esencial':   return 'No puedes eliminarlo sin impactar tu vida diaria: alquiler, servicios, comida.';
      case 'flexible':   return 'Puedes reducirlo si aprietas: streaming, salidas, suscripciones.';
      case 'importante': return 'Importante pero ajustable: cuota de ahorro, educación, extras.';
      default: return '';
    }
  }

  void _abrirFormGasto(String nombre, String tipoBackend, String clasificacionIni) {
    final montoCtrl = TextEditingController();
    String clasificacion = clasificacionIni;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('$nombre — monto mensual',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Resumen de lo ya agregado
            if (widget.gastosFijos.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ya agregados:', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                  const SizedBox(height: 4),
                  ...widget.gastosFijos.map((g) => Text(
                    '• ${g['nombre']}  B/. ${(g['monto'] as double).toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  )),
                ]),
              ),
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
            const SizedBox(height: 12),
            Row(children: [
              _TipoGastoChip('Esencial',   'esencial',   clasificacion, (v) => setDlg(() => clasificacion = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Opcional',   'flexible',   clasificacion, (v) => setDlg(() => clasificacion = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Importante', 'importante', clasificacion, (v) => setDlg(() => clasificacion = v)),
            ]),
            const SizedBox(height: 6),
            _InfoBox(_explicacion(clasificacion), small: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () async {
                final monto = double.tryParse(montoCtrl.text.replaceAll(',', ''));
                if (monto == null || monto <= 0) return;
                Navigator.pop(ctx);
                await widget.onAgregarGasto(nombre, monto, tipoBackend: tipoBackend, clasificacion: clasificacion);
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
    String clasificacion = 'esencial';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Otro gasto fijo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.gastosFijos.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ya agregados:', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                  const SizedBox(height: 4),
                  ...widget.gastosFijos.map((g) => Text(
                    '• ${g['nombre']}  B/. ${(g['monto'] as double).toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  )),
                ]),
              ),
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
            const SizedBox(height: 12),
            Row(children: [
              _TipoGastoChip('Esencial',   'esencial',   clasificacion, (v) => setDlg(() => clasificacion = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Opcional',   'flexible',   clasificacion, (v) => setDlg(() => clasificacion = v)),
              const SizedBox(width: 6),
              _TipoGastoChip('Importante', 'importante', clasificacion, (v) => setDlg(() => clasificacion = v)),
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
                await widget.onAgregarGasto(nombre, monto, tipoBackend: 'otro', clasificacion: clasificacion);
              },
              child: const Text('Agregar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).whenComplete(() { nombreCtrl.dispose(); montoCtrl.dispose(); });
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
        const SizedBox(height: 12),

        // ── Pregunta gastos compartidos ───────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _compartidos ? AppTheme.info.withValues(alpha: 0.5) : AppTheme.border),
          ),
          child: Row(children: [
            const Icon(Icons.group_outlined, color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              '¿La mayoría de tus gastos son compartidos con alguien?',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            )),
            Switch(
              value: _compartidos,
              activeColor: AppTheme.info,
              onChanged: (v) => setState(() => _compartidos = v),
            ),
          ]),
        ),
        if (_compartidos) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: AppTheme.info, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Registra tu parte personal aquí (celular, seguro, tu mitad de la renta, etc.). '
                'Después, en el menú, puedes coordinar los gastos compartidos: defines quién paga '
                'qué y la app calcula el balance automáticamente.',
                style: TextStyle(color: AppTheme.info, fontSize: 12, height: 1.4),
              )),
            ]),
          ),
        ],
        const SizedBox(height: 20),

        // ── Importar CSV ─────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Importar CSV', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _importarCsv,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Plantilla', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _descargarPlantilla,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Solo archivos .csv — exporta tu Excel como CSV primero.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 20),

        const Text('O agrega manualmente:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ...widget.sugerencias.map((s) {
            final nombre       = s['nombre'] as String;
            final icon         = s['icon'] as IconData;
            final tipoBackend  = s['tipoBackend'] as String;
            final clasificacion = s['clasificacion'] as String;
            final ya           = agregados.contains(nombre);
            return GestureDetector(
              onTap: ya ? null : () => _abrirFormGasto(nombre, tipoBackend, clasificacion),
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
              _TipoBadge((g['clasificacion'] ?? g['tipo'] ?? 'esencial') as String),
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
        // H1 — comunicar que lo que sigue es opcional (configuración rápida)
        const SizedBox(height: 10),
        Row(children: const [
          Icon(Icons.bolt_outlined, color: AppTheme.textMuted, size: 14),
          SizedBox(width: 6),
          Expanded(child: Text(
            'Con tu ingreso y gastos fijos ya tienes lo básico. Lo siguiente (deudas y '
            'presupuesto variable) es opcional: puedes saltarlo y completarlo después desde tu perfil.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.35),
          )),
        ]),
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

// ── PASO 4: GASTOS VARIABLES ─────────────────────────────────────────────────

class _Paso4Variables extends StatelessWidget {
  final Map<int, double> montos;
  final Set<int> activas;
  final List<Map<String, dynamic>> categorias;
  final double totalVariables;
  final bool guardando;
  final NumberFormat fmt;
  final void Function(int, bool) onToggle;
  final void Function(int, double) onMontoChanged;
  final VoidCallback onContinuar;

  const _Paso4Variables({
    required this.montos, required this.activas, required this.categorias,
    required this.totalVariables, required this.guardando, required this.fmt,
    required this.onToggle, required this.onMontoChanged, required this.onContinuar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 4 de 5', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('¿Cuánto quieres presupuestar al mes?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Este es tu tope objetivo por categoría (comida, ocio, etc.), no lo que ya gastaste. Puedes ajustarlo después.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),

        ...List.generate(categorias.length, (i) {
          final cat    = categorias[i];
          final activa = activas.contains(i);
          final monto  = montos[i] ?? 0.0;
          final ctrl   = TextEditingController(text: monto > 0 ? monto.toStringAsFixed(0) : '');
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: activa ? AppTheme.surface : AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: activa ? AppTheme.border : AppTheme.surfaceAlt),
              ),
              child: Row(children: [
                Icon(cat['icon'] as IconData,
                    color: activa ? AppTheme.primary : AppTheme.textMuted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(cat['nombre'] as String,
                      style: TextStyle(
                          color: activa ? AppTheme.textPrimary : AppTheme.textMuted,
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (activa) ...[
                  const Text('\$', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        border: UnderlineInputBorder(),
                      ),
                      onChanged: (v) => onMontoChanged(i, double.tryParse(v) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Switch(
                  value: activa,
                  onChanged: (v) => onToggle(i, v),
                  activeColor: AppTheme.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ]),
            ),
          );
        }),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total variables estimado',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            Text('\$${fmt.format(totalVariables)}/mes',
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: guardando ? null : onContinuar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: guardando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Continuar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: onContinuar,
            child: const Text('Saltar por ahora', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ),
      ]),
    );
  }
}

// ── PASO 5: RESUMEN ───────────────────────────────────────────────────────────

class _Paso5Resumen extends StatelessWidget {
  final double ingresoNeto;
  final double totalFijos;
  final double totalDeudas;
  final double totalVariables;
  final double remanente;
  final int cantGastos;
  final int cantDeudas;
  final int cantVariables;
  final NumberFormat fmt;
  final bool generando;
  final VoidCallback onGenerar;
  final VoidCallback onIrAPaso1;
  final VoidCallback onIrAGastos;
  const _Paso5Resumen({
    required this.ingresoNeto, required this.totalFijos, required this.totalDeudas,
    required this.totalVariables, required this.remanente,
    required this.cantGastos, required this.cantDeudas, required this.cantVariables,
    required this.fmt, required this.generando, required this.onGenerar,
    required this.onIrAPaso1, required this.onIrAGastos,
  });

  @override
  Widget build(BuildContext context) {
    final sinIngreso = ingresoNeto <= 0;
    final remColor = remanente >= 0 ? AppTheme.success : AppTheme.danger;
    if (sinIngreso) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 56),
          const SizedBox(height: 20),
          const Text('Falta tu ingreso',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'Para generar tu estado financiero necesitas registrar cuánto ganas.\n\nVuelve al Paso 1 y completa tu ingreso.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 18),
              label: const Text('Ir al Paso 1 — Registrar ingreso',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onIrAPaso1,
            ),
          ),
        ]),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paso 5 de 5', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
            if (cantVariables > 0) ...[
              const SizedBox(height: 6),
              _ResRow('Variables estimadas ($cantVariables)',
                  '− B/. ${fmt.format(totalVariables)}', AppTheme.warning),
            ],
            const Divider(color: AppTheme.border, height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Te sobra al mes',
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Tus compromisos superan tu ingreso.',
                  style: TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w700),
                )),
              ]),
              const SizedBox(height: 6),
              const Text(
                'No estás solo/a en esto. Salarying te ayudará a entender dónde ajustar. Puedes revisar tus gastos ahora o continuar y ajustarlos después.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: onIrAGastos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: const BorderSide(color: AppTheme.warning),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Revisar mis gastos', style: TextStyle(fontSize: 12)),
                )),
              ]),
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
              generando ? 'Preparando tu plan...' : 'Comenzar a controlar mi dinero →',
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

// ── Diálogo de revisión CSV ───────────────────────────────────────────────────

class _RevisionCsvDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(List<Map<String, dynamic>>) onConfirmar;
  const _RevisionCsvDialog({required this.rows, required this.onConfirmar});
  @override
  State<_RevisionCsvDialog> createState() => _RevisionCsvDialogState();
}

class _RevisionCsvDialogState extends State<_RevisionCsvDialog> {
  late final List<Map<String, dynamic>> _rows;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  double get _total => _rows.fold(0.0, (s, r) => s + (r['monto_mensual'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.checklist_outlined, color: AppTheme.primary, size: 20),
        const SizedBox(width: 8),
        Text('Revisar importación (${_rows.length})',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Row(children: [
            SizedBox(width: 28),
            Expanded(flex: 3, child: Text('Descripción', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: Text('Monto', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: Text('Tipo', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
          ]),
          const Divider(color: AppTheme.border, height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    // Eliminar fila
                    GestureDetector(
                      onTap: () => setState(() => _rows.removeAt(i)),
                      child: const Icon(Icons.remove_circle_outline, color: AppTheme.textMuted, size: 16),
                    ),
                    const SizedBox(width: 6),
                    // Descripción (editable)
                    Expanded(flex: 3, child: TextFormField(
                      initialValue: r['descripcion'] as String,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        filled: true, fillColor: AppTheme.surfaceAlt,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => _rows[i]['descripcion'] = v,
                    )),
                    const SizedBox(width: 6),
                    // Monto (editable)
                    Expanded(flex: 2, child: TextFormField(
                      initialValue: (r['monto_mensual'] as num).toStringAsFixed(2),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        filled: true, fillColor: AppTheme.surfaceAlt,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        prefixText: 'B/.',
                        prefixStyle: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      onChanged: (v) {
                        final d = double.tryParse(v);
                        if (d != null) setState(() => _rows[i]['monto_mensual'] = d);
                      },
                    )),
                    const SizedBox(width: 6),
                    // Clasificación
                    Expanded(flex: 2, child: _ClasifDropdown(
                      value: r['clasificacion'] as String,
                      onChanged: (v) => setState(() => _rows[i]['clasificacion'] = v),
                    )),
                  ]),
                );
              },
            ),
          ),
          const Divider(color: AppTheme.border, height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${_rows.length} gastos · Total mensual',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            Text('B/. ${_total.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: _guardando
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.check, size: 16, color: Colors.black),
          label: Text(_guardando ? 'Guardando...' : 'Importar ${_rows.length} gastos',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _guardando || _rows.isEmpty ? null : () async {
            setState(() => _guardando = true);
            await widget.onConfirmar(_rows);
          },
        ),
      ],
    );
  }
}

class _ClasifDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ClasifDropdown({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    isDense: true,
    decoration: const InputDecoration(
      isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      filled: true, fillColor: AppTheme.surfaceAlt,
      border: OutlineInputBorder(borderSide: BorderSide.none),
    ),
    dropdownColor: AppTheme.surface,
    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
    items: const [
      DropdownMenuItem(value: 'esencial',   child: Text('Esencial')),
      DropdownMenuItem(value: 'importante', child: Text('Importante')),
      DropdownMenuItem(value: 'flexible',   child: Text('Opcional')),
    ],
    onChanged: (v) { if (v != null) onChanged(v); },
  );
}

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
      case 'esencial':    color = AppTheme.success; label = 'esencial';   break;
      case 'flexible':
      case 'no_esencial': color = AppTheme.warning;  label = 'opcional';   break;
      case 'importante':
      case 'ahorro':      color = AppTheme.info;     label = 'importante'; break;
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
