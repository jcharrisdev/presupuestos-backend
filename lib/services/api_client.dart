/// Capa de comunicación HTTP centralizada para toda la app.
///
/// Todos los widgets y pantallas deben usar [ApiClient] en lugar de
/// instanciar `http.Client` directamente. Esto garantiza que:
///   1. La URL base del backend siempre sea la misma.
///   2. El token de autenticación se inyecte automáticamente en cada petición.
///   3. Cuando se integre Firebase Auth, solo habrá UN lugar donde cambiar.
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cliente HTTP estático con soporte para autenticación Bearer.
///
/// Todos los métodos son estáticos (no necesitas instanciar la clase).
/// Ejemplo de uso:
/// ```dart
/// final res = await ApiClient.get('/presupuestos?firebase_uid=xxx');
/// final res = await ApiClient.post('/gastos', {'descripcion': 'Alquiler', ...});
/// ```
class ApiClient {
  /// URL base del backend desplegado en Render.
  /// Cambiar aquí si el backend se mueve a otra plataforma.
  static const String baseUrl = 'https://presupuestos-backend-h3l6.onrender.com';

  /// Token de autenticación Bearer (Firebase Auth en sprint futuro).
  /// Por ahora queda null — no se envía header Authorization.
  static String? _token;

  /// Guarda el token recibido tras el login con Firebase Auth.
  /// Una vez asignado, se incluirá automáticamente en todas las peticiones.
  static void setToken(String token) => _token = token;

  /// Limpia el token al hacer logout (llamar desde la pantalla de cierre de sesión).
  static void clearToken() => _token = null;

  /// Construye los headers comunes para todas las peticiones.
  /// Si hay token activo, agrega `Authorization: Bearer <token>`.
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// GET a `baseUrl + path`.
  /// [path] debe comenzar con `/`, p.ej. `/presupuestos?firebase_uid=xxx`.
  static Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: _headers);

  /// POST a `baseUrl + path` con cuerpo JSON codificado.
  /// [body] se serializa automáticamente con `jsonEncode`.
  static Future<http.Response> post(String path, Map<String, dynamic> body) =>
      http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));

  /// PUT a `baseUrl + path` con cuerpo JSON codificado.
  /// Usado para actualizar recursos existentes (presupuestos, movimientos, etc.).
  static Future<http.Response> put(String path, Map<String, dynamic> body) =>
      http.put(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));

  /// DELETE a `baseUrl + path`.
  /// Algunos DELETE llevan parámetros en la query string, p.ej.
  /// `/produccion/items/5?firebase_uid=xxx`.
  static Future<http.Response> delete(String path) =>
      http.delete(Uri.parse('$baseUrl$path'), headers: _headers);
}
