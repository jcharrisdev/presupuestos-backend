import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'home_shell.dart';
import 'services/auth_service.dart';

/// Pantalla de inicio de sesión — solo Google/Gmail.
///
/// Al autenticarse correctamente navega a [HomeShell] con el email
/// de la cuenta Google como `firebaseUid`, preservando todos los
/// datos existentes en la base de datos sin necesidad de migración.
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _navegarConUid(String email, {String? displayName}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeShell(
          firebaseUid: email.trim().toLowerCase(),
          displayName: displayName,
          photoUrl: null,
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final account = await AuthService.signIn();
      if (!mounted) return;
      if (account != null) _navegarConUid(account.email, displayName: account.displayName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar sesión: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _signInWithEmail() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un email válido')),
      );
      return;
    }
    _navegarConUid(email);
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
              children: [
                // ── LOGO ──────────────────────────────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: AppTheme.background, size: 38),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Salarying',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gestiona tus finanzas personales',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),

                const SizedBox(height: 64),

                if (_loading)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                else if (kIsWeb)
                  // ── WEB: campo de email ────────────────────────────────────
                  Column(children: [
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Tu email de Gmail',
                        hintText: 'ejemplo@gmail.com',
                        prefixIcon: const Icon(Icons.email_outlined,
                            color: AppTheme.textSecondary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _signInWithEmail(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _signInWithEmail,
                        child: const Text('Entrar', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Usa el mismo email con el que iniciaste sesión en la app móvil',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ])
                else
                  // ── MÓVIL: Google Sign-In ──────────────────────────────────
                  Column(children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: _GoogleSignInButton(onPressed: _signInWithGoogle),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Usa tu cuenta de Gmail para acceder',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón con la marca de Google conforme a sus guidelines de diseño.
class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _GoogleSignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3C4043),
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDADCE0)),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _GoogleLogo(),
          const SizedBox(width: 12),
          const Text(
            'Continuar con Google',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }
}

/// Logo "G" de Google con sus colores oficiales usando CustomPaint.
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GLogoPainter()),
    );
  }
}

class _GLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.16;

    // Arco azul (top-right, right, bottom-right)
    _drawArc(canvas, rect, center, radius, strokeWidth, -0.25, 0.6, const Color(0xFF4285F4));
    // Arco rojo (top-left)
    _drawArc(canvas, rect, center, radius, strokeWidth, -0.75, 0.25, const Color(0xFFEA4335));
    // Arco amarillo (bottom-left)
    _drawArc(canvas, rect, center, radius, strokeWidth, -0.5, 0.27, const Color(0xFFFBBC05));
    // Arco verde (bottom)
    _drawArc(canvas, rect, center, radius, strokeWidth, 0.2, 0.32, const Color(0xFF34A853));

    // Barra horizontal derecha del "G"
    final paint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(size.width * 0.9, center.dy),
      paint,
    );
  }

  void _drawArc(Canvas canvas, Rect rect, Offset center, double radius,
      double strokeWidth, double startTurns, double sweepTurns, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    final innerRadius = radius - strokeWidth / 2;
    final arcRect = Rect.fromCircle(center: center, radius: innerRadius);

    canvas.drawArc(
      arcRect,
      startTurns * 2 * 3.14159,
      sweepTurns * 2 * 3.14159,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
