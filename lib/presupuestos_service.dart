/// Servicio de acceso a datos para el módulo de presupuestos.
///
/// Envuelve las llamadas HTTP de [ApiClient] en métodos tipados,
/// de modo que [ListaPresupuestos] no necesita conocer URLs ni
/// parseo de JSON directamente.
///
/// Si en el futuro se cambia el backend o se agrega caché local,
/// solo este archivo debe modificarse.
import 'dart:convert';
import 'services/api_client.dart';

/// Capa de servicio para operaciones de presupuestos.
class PresupuestoService {
  /// Obtiene todos los presupuestos del usuario identificado por [firebaseUid].
  ///
  /// Retorna una lista de objetos JSON con al menos:
  /// `id`, `nombre`, `monto_total`, `tipo_periodo`, `dia_inicio_periodo`.
  ///
  /// Lanza [Exception] si el servidor retorna un código distinto de 200.
  Future<List<dynamic>> obtenerPresupuestos(String firebaseUid) async {
    final response = await ApiClient.get('/presupuestos?firebase_uid=$firebaseUid');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Error al obtener los presupuestos (${response.statusCode})');
  }
}
