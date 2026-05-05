import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static late Box _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('salarying_cache');
  }

  static Future<void> set(String key, dynamic data) async {
    await _box.put(key, {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static dynamic get(String key, {Duration maxAge = const Duration(hours: 24)}) {
    final entry = _box.get(key);
    if (entry == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - (entry['timestamp'] as int);
    if (age > maxAge.inMilliseconds) return null;
    return entry['data'];
  }

  static Future<void> clearForUser(String uid) async {
    final keys = _box.keys.where((k) => k.toString().startsWith('${uid}_')).toList();
    await _box.deleteAll(keys);
  }

  static Future<void> clear() => _box.clear();
}
