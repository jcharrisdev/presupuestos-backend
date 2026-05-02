/// Pantalla de inicio de sesión de Salarying.
///
/// ESTADO ACTUAL (sprint 1): autenticación simplificada.
/// El email ingresado SE USA DIRECTAMENTE como `firebase_uid` en todas
/// las peticiones al backend. No hay contraseña ni validación real.
///
/// SPRINT FUTURO: se reemplazará por Firebase Auth (`signInWithEmailAndPassword`).
/// Al integrar Firebase, el UID será el de Firebase y el email solo se usará
/// como credencial. La migración estará aislada aquí y en [ApiClient.setToken].
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'main_menu.dart';

/// Pantalla de login con campo de email.
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Controlador del campo de email.
  final _emailCtrl = TextEditingController();

  /// true mientras se procesa el "login" (300ms de delay para feedback visual).
  bool _loading = false;

  /// Ejecuta el inicio de sesión.
  ///
  /// Valida que el email no esté vacío, muestra el spinner 300ms y
  /// navega a [MainMenu] pasando el email como `firebaseUid`.
  /// `pushReplacement` evita que el botón "atrás" regrese al login.
  void _login() {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu email para continuar')),
      );
      return;
    }
    setState(() => _loading = true);

    // Delay mínimo para que el spinner sea visible antes de navegar
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainMenu(firebaseUid: email)),
      );
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── LOGO / BRAND ──────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      // Ícono de la app sobre fondo amarillo con esquinas redondeadas
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: AppTheme.background, size: 34),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Salarying',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Gestiona tus finanzas personales',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // ── FORMULARIO ────────────────────────────────────────────────
                const Text('Correo electrónico', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  // Permite enviar el form con el teclado
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    hintText: 'ejemplo@correo.com',
                    prefixIcon: Icon(Icons.mail_outline, color: AppTheme.textSecondary, size: 18),
                  ),
                ),

                const SizedBox(height: 28),

                // Botón principal / spinner de carga
                SizedBox(
                  width: double.infinity,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                      : ElevatedButton(
                          onPressed: _login,
                          child: const Text('Ingresar'),
                        ),
                ),

                const SizedBox(height: 32),

                // ── AVISO TEMPORAL ────────────────────────────────────────────
                // Informa al usuario que la autenticación real viene pronto
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.primary, size: 15),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Autenticación Firebase disponible próximamente.',
                          style: TextStyle(color: AppTheme.primary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
