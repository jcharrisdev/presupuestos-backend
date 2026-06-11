import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/money.dart';

class PdfService {
  static final _h1 = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800);
  static final _h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700);
  static final _body = pw.TextStyle(fontSize: 11, color: PdfColors.grey700);
  static final _bodySmall = pw.TextStyle(fontSize: 10, color: PdfColors.grey600);
  static final _mono = pw.TextStyle(fontSize: 11, color: PdfColors.grey900);

  static double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  static Future<Uint8List> generarPdfVenta(
    Map<String, dynamic> venta,
    List<dynamic> cobros,
    Map<String, dynamic> resumen,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final fmtDate = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';

    final invertido  = _d(resumen['total_invertido']);
    final cobrado    = _d(resumen['total_cobrado']);
    final esperado   = _d(resumen['total_esperado']);
    final ganancia   = cobrado - invertido;
    final margen     = cobrado > 0 ? (ganancia / cobrado * 100) : 0.0;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Salarying', style: _h1.copyWith(color: PdfColors.amber700)),
        pw.SizedBox(height: 4),
        pw.Text(venta['nombre']?.toString() ?? 'Venta', style: _h2),
        pw.Text('Generado: $fmtDate', style: _bodySmall),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 8),
      ]),
      footer: (_) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Generado con Salarying · $fmtDate', style: _bodySmall),
      ),
      build: (_) => [
        // RESUMEN
        pw.Text('RESUMEN', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
          children: [
            _tr('Invertido', '${Money.fmt(invertido)}'),
            _tr('Total Cobrado', '${Money.fmt(cobrado)}', color: PdfColors.green700),
            _tr('Total Esperado', '${Money.fmt(esperado)}'),
            _tr('Ganancia', '${Money.fmt(ganancia)}', color: ganancia >= 0 ? PdfColors.green700 : PdfColors.red700),
            _tr('Margen', '${margen.toStringAsFixed(1)}%'),
          ],
        ),
        pw.SizedBox(height: 20),

        // COBROS
        pw.Text('COBROS', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Table.fromTextArray(
          headers: ['Cliente', 'Monto', 'Estado', 'Fecha'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          data: cobros.map((c) {
            final monto = _d(c['monto']);
            final estado = c['estado']?.toString() ?? '';
            final fecha = c['fecha_cobrado']?.toString() ?? c['fecha_cobro']?.toString() ?? '-';
            return [
              c['nombre_cliente']?.toString() ?? '',
              '${Money.fmt(monto)}',
              estado,
              fecha.length >= 10 ? fecha.substring(0, 10) : fecha,
            ];
          }).toList(),
        ),
      ],
    ));

    return doc.save();
  }

  static Future<Uint8List> generarPdfPresupuesto(
    Map<String, dynamic> presupuesto,
    List<dynamic> movimientos,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final fmtDate = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';
    final nombre = presupuesto['nombre']?.toString() ?? 'Presupuesto';
    final montoTotal = _d(presupuesto['monto_total']);
    final totalPagado = movimientos.fold<double>(0, (s, m) => s + _d(m['monto_pagado_real']));
    final disponible = montoTotal - totalPagado;

    // Agrupar por tipo
    final fijos    = movimientos.where((m) => m['tipo'] == 'fijo' || m['tipo'] == 'fijo_x_periodo').toList();
    final variable = movimientos.where((m) => m['tipo'] == 'no fijo').toList();
    final ahorro   = movimientos.where((m) => m['tipo'] == 'ahorro').toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Salarying', style: _h1.copyWith(color: PdfColors.amber700)),
        pw.SizedBox(height: 4),
        pw.Text(nombre, style: _h2),
        pw.Text('Generado: $fmtDate', style: _bodySmall),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 8),
      ]),
      footer: (_) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Generado con Salarying · $fmtDate', style: _bodySmall),
      ),
      build: (_) => [
        // BALANCE
        pw.Text('BALANCE', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
          children: [
            _tr('Presupuesto total', '${Money.fmt(montoTotal)}'),
            _tr('Total pagado', '${Money.fmt(totalPagado)}', color: PdfColors.green700),
            _tr('Disponible', '${Money.fmt(disponible)}', color: disponible >= 0 ? PdfColors.green700 : PdfColors.red700),
          ],
        ),
        pw.SizedBox(height: 20),

        if (fijos.isNotEmpty) ...[
          _seccionMovimientos('FIJOS', fijos),
          pw.SizedBox(height: 12),
        ],
        if (variable.isNotEmpty) ...[
          _seccionMovimientos('VARIABLES', variable),
          pw.SizedBox(height: 12),
        ],
        if (ahorro.isNotEmpty) ...[
          _seccionMovimientos('AHORRO', ahorro),
        ],
      ],
    ));

    return doc.save();
  }

  static pw.TableRow _tr(String label, String value, {PdfColor? color}) => pw.TableRow(children: [
    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(label, style: _body)),
    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(value, style: _mono.copyWith(color: color))),
  ]);

  static pw.Widget _seccionMovimientos(String titulo, List movs) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(titulo, style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
      pw.SizedBox(height: 4),
      pw.Table.fromTextArray(
        headers: ['Descripción', 'Monto', 'Pagado', 'Fecha pago'],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        data: movs.map((m) {
          final pagado = m['pagado'] == 1 || m['pagado'] == true;
          final monto = _d(m['monto']);
          final real = _d(m['monto_pagado_real']);
          final fecha = m['fecha_pagado']?.toString() ?? '-';
          return [
            m['descripcion']?.toString() ?? '',
            '${Money.fmt(monto)}',
            pagado ? '${Money.fmt(real)}' : 'pendiente',
            fecha.length >= 10 ? fecha.substring(0, 10) : fecha,
          ];
        }).toList(),
      ),
    ],
  );

  static Future<Uint8List> generarPdfMes(
    Map<String, dynamic> data,
    String labelMes,
    int anio,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final fmtDate = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';
    final r   = (data['resumen'] as Map<String, dynamic>? ?? {});
    final reg = (data['registros'] as List? ?? []).cast<Map<String, dynamic>>();
    final compromisos = (data['compromisos_fijos'] as Map<String, dynamic>? ?? {});
    final gastosFijos = (compromisos['gastos_fijos'] as List? ?? []).cast<Map<String, dynamic>>();
    final deudas      = (compromisos['deudas']       as List? ?? []).cast<Map<String, dynamic>>();

    pw.Widget _fila(String label, double est, double real, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.Expanded(flex: 3, child: pw.Text(label, style: bold ? _h2 : _body)),
        pw.Expanded(child: pw.Text('${Money.fmt(est)}', style: bold ? _h2 : _body, textAlign: pw.TextAlign.right)),
        pw.Expanded(child: pw.Text('${Money.fmt(real)}',
            style: (bold ? _h2 : _body).copyWith(color: real > est ? PdfColors.red700 : PdfColors.green700),
            textAlign: pw.TextAlign.right)),
      ]),
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Salarying', style: _h1.copyWith(color: PdfColors.amber700)),
          pw.Text('$labelMes $anio', style: _h2),
        ]),
        pw.Text('Estado financiero mensual · Generado: $fmtDate', style: _bodySmall),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 4),
      ]),
      footer: (_) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Generado con Salarying · salarying.app', style: _bodySmall),
      ),
      build: (_) => [
        // BALANCE
        pw.Text('BALANCE DEL MES', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Expanded(flex: 3, child: pw.Text('Concepto', style: _bodySmall)),
          pw.Expanded(child: pw.Text('Planificado', style: _bodySmall, textAlign: pw.TextAlign.right)),
          pw.Expanded(child: pw.Text('Real', style: _bodySmall, textAlign: pw.TextAlign.right)),
        ]),
        pw.Divider(color: PdfColors.grey200),
        _fila('Ingreso', _d(r['ingreso_estimado']), _d(r['ingreso_real'])),
        _fila('Gastos fijos', _d(r['fijos_estimados']), _d(r['fijos_reales'])),
        _fila('Gastos variables', _d(r['variables_estimados']), _d(r['variables_reales'])),
        pw.Divider(color: PdfColors.grey300),
        _fila('Te sobró', _d(r['remanente_estimado']), _d(r['remanente_real']), bold: true),
        pw.SizedBox(height: 20),

        // COMPROMISOS FIJOS
        if (gastosFijos.isNotEmpty || deudas.isNotEmpty) ...[
          pw.Text('COMPROMISOS FIJOS DEL MES', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
          pw.SizedBox(height: 6),
          ...gastosFijos.map((g) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text(g['nombre']?.toString() ?? '—', style: _body)),
              pw.Text('${Money.fmt(_d(g['monto_mensual']))}', style: _body),
            ]),
          )),
          ...deudas.map((d) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text('${d['nombre']} (deuda)', style: _body)),
              pw.Text('${Money.fmt(_d(d['cuota']))}', style: _body),
            ]),
          )),
          pw.SizedBox(height: 20),
        ],

        // GASTOS REGISTRADOS
        if (reg.isNotEmpty) ...[
          pw.Text('GASTOS REGISTRADOS (${reg.length})', style: _h2.copyWith(color: PdfColors.grey500, fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Expanded(flex: 3, child: pw.Text('Descripción', style: _bodySmall)),
            pw.Expanded(child: pw.Text('Categoría', style: _bodySmall)),
            pw.Expanded(child: pw.Text('Monto', style: _bodySmall, textAlign: pw.TextAlign.right)),
          ]),
          pw.Divider(color: PdfColors.grey200),
          ...reg.map((g) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.Expanded(flex: 3, child: pw.Text(g['nombre']?.toString() ?? '—', style: _body)),
              pw.Expanded(child: pw.Text(g['categoria']?.toString() ?? '', style: _bodySmall)),
              pw.Expanded(child: pw.Text('${Money.fmt(_d(g['monto']))}', style: _body, textAlign: pw.TextAlign.right)),
            ]),
          )),
        ],
      ],
    ));
    return doc.save();
  }
}
