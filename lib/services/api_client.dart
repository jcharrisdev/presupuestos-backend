/// Capa de comunicación HTTP centralizada para toda la app.
///
/// Todos los widgets y pantallas deben usar [ApiClient] en lugar de
/// instanciar `http.Client` directamente. Esto garantiza que:
///   1. La URL base del backend siempre sea la misma.
///   2. El token de autenticación se inyecte automáticamente en cada petición.
///   3. Cuando se integre Firebase Auth, solo habrá UN lugar donde cambiar.
///   4. El timeout de red se aplica globalmente (evita pantallas colgadas).
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cliente HTTP estático con soporte para autenticación Bearer y timeout global.
///
/// Todos los métodos son estáticos (no necesitas instanciar la clase).
/// Ejemplo de uso:
/// ```dart
/// final res = await ApiClient.get('/presupuestos?firebase_uid=xxx');
/// final res = await ApiClient.post('/gastos', {'descripcion': 'Alquiler', ...});
/// ```
class ApiClient {
  /// URL base del backend desplegado en Render.
  static const String baseUrl = 'https://presupuestos-backend-h3l6.onrender.com';

  /// Timeout global para todas las peticiones.
  ///
  /// Render (plan gratuito) duerme tras 15 minutos sin tráfico y tarda
  /// hasta 50 segundos en despertar. Sin timeout, la app se queda colgada
  /// mostrando solo el spinner. Con 55s el primer request tras una pausa
  /// larga tiene oportunidad de completar; los demás son instantáneos.
  static const Duration _timeout = Duration(seconds: 55);

  /// Token de autenticación Bearer (Firebase Auth en sprint futuro).
  static String? _token;

  /// Guarda el token recibido tras el login con Firebase Auth.
  static void setToken(String token) => _token = token;

  /// Limpia el token al hacer logout.
  static void clearToken() => _token = null;

  /// Headers comunes. Incluye Authorization si hay token activo.
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// GET con timeout. Lanza [TimeoutException] si el servidor no responde.
  static Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: _headers).timeout(_timeout);

  /// POST con timeout.
  static Future<http.Response> post(String path, Map<String, dynamic> body) =>
      http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);

  /// PUT con timeout.
  static Future<http.Response> put(String path, Map<String, dynamic> body) =>
      http.put(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);

  /// DELETE con timeout.
  static Future<http.Response> delete(String path) =>
      http.delete(Uri.parse('$baseUrl$path'), headers: _headers).timeout(_timeout);
}
