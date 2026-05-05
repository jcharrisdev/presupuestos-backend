import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
            _tr('Invertido', '\$${invertido.toStringAsFixed(2)}'),
            _tr('Total Cobrado', '\$${cobrado.toStringAsFixed(2)}', color: PdfColors.green700),
            _tr('Total Esperado', '\$${esperado.toStringAsFixed(2)}'),
            _tr('Ganancia', '\$${ganancia.toStringAsFixed(2)}', color: ganancia >= 0 ? PdfColors.green700 : PdfColors.red700),
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
              '\$${monto.toStringAsFixed(2)}',
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
            _tr('Presupuesto total', '\$${montoTotal.toStringAsFixed(2)}'),
            _tr('Total pagado', '\$${totalPagado.toStringAsFixed(2)}', color: PdfColors.green700),
            _tr('Disponible', '\$${disponible.toStringAsFixed(2)}', color: disponible >= 0 ? PdfColors.green700 : PdfColors.red700),
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
            '\$${monto.toStringAsFixed(2)}',
            pagado ? '\$${real.toStringAsFixed(2)}' : 'pendiente',
            fecha.length >= 10 ? fecha.substring(0, 10) : fecha,
          ];
        }).toList(),
      ),
    ],
  );
}
