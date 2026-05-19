import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme/app_theme.dart';
import 'login_screen.dart';
import 'home_shell.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/cache_service.dart';

// RouteObserver global: permite que VentaDetalle detecte cuando vuelve al foco
// (didPopNext) y recargue datos — fix Bug 1 (cobrado desde calendario no actualizaba).
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('es', null);
  await CacheService.init();
  await NotificationService.init();
  await NotificationService.requestPermission();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salarying',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      navigatorObservers: [routeObserver],
      home: const _AuthGate(),
    );
  }
}

/// Decide la pantalla inicial revisando si hay sesión activa de Google.
///
/// - Muestra un splash mientras resuelve el silent sign-in.
/// - Si hay sesión → va directo a [MainMenu] (evita el login manual).
/// - Si no → muestra [LoginScreen].
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GoogleSignInAccount?>(
      future: AuthService.silentSignIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        final account = snapshot.data;
        if (account != null) {
          return HomeShell(
            firebaseUid: account.email!,
            displayName: account.displayName,
            photoUrl: account.photoUrl,
          );
        }
        return const LoginScreen();
      },
    );
  }
}

/// Pantalla de carga mientras se verifica la sesión de Google.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.account_balance_wallet, color: AppTheme.background, size: 38),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
