import 'package:flutter/material.dart';

// Pantallas
import 'login_screen.dart';
import 'calendario.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor Financiero',
      debugShowCheckedModeBanner: false,

      // 🔑 La app SIEMPRE inicia en login
      home: const LoginScreen(),

      // 🚫 SOLO rutas que NO requieren argumentos
      routes: {
        '/calendario': (context) => CalendarioScreen(),
      },
    );
  }
}
