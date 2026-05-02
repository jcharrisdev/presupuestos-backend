/// Punto de entrada de la aplicación Salarying.
///
/// Secuencia de arranque:
///   1. `initializeDateFormatting('es', null)` — registra los símbolos de fecha
///      en español para que `DateFormat('EEEE, d MMMM', 'es')` funcione en el
///      calendario (lunes, martes… enero, febrero…).
///   2. `NotificationService.init()` — crea el canal de notificaciones de Android.
///   3. `NotificationService.requestPermission()` — solicita permiso en Android 13+.
///   4. `setSystemUIOverlayStyle` — status bar transparente con íconos blancos,
///      coherente con el fondo oscuro de la app.
///   5. `runApp(MyApp())` — inicia el árbol de widgets.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_theme.dart';
import 'login_screen.dart';
import 'services/notification_service.dart';

/// Función principal asíncrona requerida por Flutter para operaciones
/// de inicialización antes de mostrar la primera pantalla.
void main() async {
  // Necesario cuando se hacen awaits antes de runApp
  WidgetsFlutterBinding.ensureInitialized();

  // Carga los datos de localización en español (nombres de días y meses)
  await initializeDateFormatting('es', null);

  // Inicializa el canal de notificaciones locales y pide permiso
  await NotificationService.init();
  await NotificationService.requestPermission();

  // Hace la barra de estado transparente con íconos claros (tema oscuro)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

/// Widget raíz de la aplicación.
///
/// Configura el [MaterialApp] con:
/// - Título de la app en el task manager del SO
/// - Tema oscuro estilo Binance de [AppTheme]
/// - Pantalla inicial: [LoginScreen]
/// - Debug banner oculto
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salarying',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const LoginScreen(),
    );
  }
}
