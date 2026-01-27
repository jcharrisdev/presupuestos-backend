import 'package:flutter/material.dart';

class CalendarioScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calendario de Pagos / Cobros'),
        backgroundColor: Color(0xFF6ABF69), // Color verde
      ),
      body: Center(
        child: Text(
          'Pantalla de Calendario en desarrollo',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
