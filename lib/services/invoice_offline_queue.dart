import 'package:hive_flutter/hive_flutter.dart';
import 'invoice_scanner_service.dart';

class InvoiceOfflineQueue {
  static const _boxName = 'pending_scans';

  static Future<void> init() async {
    await Hive.openBox<Map>(_boxName);
  }

  static Future<void> queueScan(String qrContent, String firebaseUid) async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<Map>(_boxName);
    }
    final box = Hive.box<Map>(_boxName);
    await box.add({'qr_content': qrContent, 'firebase_uid': firebaseUid});
  }

  static int get pendingCount {
    if (!Hive.isBoxOpen(_boxName)) return 0;
    return Hive.box<Map>(_boxName).length;
  }

  static Future<List<Map<String, dynamic>>> syncPendingScans() async {
    if (!Hive.isBoxOpen(_boxName)) return [];
    final box = Hive.box<Map>(_boxName);
    if (box.isEmpty) return [];

    final synced = <Map<String, dynamic>>[];
    final keysToDelete = <int>[];

    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry == null) continue;
      try {
        final result = await InvoiceScannerService.processQrScan(
          entry['qr_content'] as String,
          entry['firebase_uid'] as String,
        );
        keysToDelete.add(key as int);
        synced.add(result);
      } catch (_) {
        // Mantener en queue si falla
      }
    }

    for (final k in keysToDelete) {
      await box.delete(k);
    }
    return synced;
  }
}
