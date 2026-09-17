import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salarying/mes_detalle_screen.dart';
import 'package:salarying/utils/money.dart';
import 'package:salarying/widgets/financiero/resumen_mensual_card.dart';

void main() {
  final resumen = <String, dynamic>{
    'ingreso_real': 1000,
    'gastos_registrados': 500,
    'gastos_pagados': 200,
    'gastos_pendientes': 100,
    'compromisos_pendientes': 200,
    'total_pendiente': 300,
    'disponible_real': 800,
    'disponible_proyectado': 500,
  };

  test('una respuesta anterior o incompleta no se presenta como resumen de caja', () {
    expect(ResumenMensualCard.tieneDatos({'remanente_real': 500}), isFalse);
    expect(ResumenMensualCard.tieneDatos(resumen), isTrue);
    expect(ResumenMensualCard.tieneDatos({...resumen, 'total_pendiente': null}), isFalse);
    expect(ResumenMensualCard.tieneDatos({...resumen, 'disponible_real': 'NaN'}), isFalse);
  });

  test('normaliza el estado pagado recibido desde MySQL y JSON', () {
    for (final valor in [true, 1, '1']) {
      expect(registroEstaPagado(valor), isTrue, reason: 'valor: $valor');
    }
    for (final valor in [false, 0, '0', null]) {
      expect(registroEstaPagado(valor), isFalse, reason: 'valor: $valor');
    }
  });

  testWidgets('presenta pagos y pendientes con los valores del servidor en pantalla estrecha', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ResumenMensualCard(resumen: resumen))),
    ));
    expect(find.text('Disponible tras pagos'), findsOneWidget);
    expect(find.text(Money.fmt(800)), findsOneWidget);
    expect(find.text('Total pendiente'), findsOneWidget);
    expect(find.text(Money.fmt(300)), findsOneWidget);
    expect(find.text('Tras pagar los pendientes'), findsOneWidget);
    expect(find.text(Money.fmt(500)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conserva el importe negativo y muestra el aviso de pendientes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResumenMensualCard(resumen: {
        ...resumen, 'ingreso_real': 0, 'gastos_pagados': 0,
        'disponible_real': 0, 'disponible_proyectado': -100,
      })),
    ));
    expect(find.text(Money.fmt(-100)), findsOneWidget);
    expect(find.text('Los pagos pendientes superan tu disponible.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
