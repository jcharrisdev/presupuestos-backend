import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'https://presupuestos-backend-h3l6.onrender.com';

  // Slot para token de autenticación (Firebase Auth en sprint siguiente)
  static String? _token;

  static void setToken(String token) => _token = token;
  static void clearToken() => _token = null;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: _headers);

  static Future<http.Response> post(String path, Map<String, dynamic> body) =>
      http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));

  static Future<http.Response> put(String path, Map<String, dynamic> body) =>
      http.put(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));

  static Future<http.Response> delete(String path) =>
      http.delete(Uri.parse('$baseUrl$path'), headers: _headers);
}
