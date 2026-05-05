import 'package:google_sign_in/google_sign_in.dart';
import 'cache_service.dart';

/// Wrapper de Google Sign-In.
///
/// Usa el email de la cuenta Google como identificador de usuario (`firebase_uid`),
/// lo que preserva todos los datos existentes en la base de datos sin migraciones.
class AuthService {
  static final _googleSignIn = GoogleSignIn(scopes: ['email']);

  /// Abre el selector de cuenta de Google. Retorna null si el usuario cancela.
  static Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();

  /// Recupera la sesión silenciosamente al iniciar la app.
  /// Retorna null si no hay sesión previa o si ocurre cualquier error.
  static Future<GoogleSignInAccount?> silentSignIn() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  /// Cierra la sesión del usuario actual y limpia el caché local del usuario.
  static Future<void> signOut() async {
    final user = _googleSignIn.currentUser;
    if (user != null) await CacheService.clearForUser(user.email);
    await _googleSignIn.signOut();
  }

  /// Usuario actualmente autenticado, o null si no hay sesión.
  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
}
