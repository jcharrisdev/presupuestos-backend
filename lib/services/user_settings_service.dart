import 'dart:convert';
import 'api_client.dart';

class UserSettingsService {
  static Future<Map<String, dynamic>> get(String uid) async {
    try {
      final res = await ApiClient.get('/user/settings?firebase_uid=$uid');
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (_) {}
    return {'modo_negocio': 0};
  }

  static Future<bool> setModoNegocio(String uid, bool activo) async {
    try {
      final res = await ApiClient.patch('/user/settings', {
        'firebase_uid': uid,
        'modo_negocio': activo ? 1 : 0,
      });
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
