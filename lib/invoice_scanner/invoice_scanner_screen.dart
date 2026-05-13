import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../services/invoice_scanner_service.dart';
import '../services/invoice_offline_queue.dart';
import 'invoice_preview_screen.dart';

class InvoiceScannerScreen extends StatefulWidget {
  final String firebaseUid;
  const InvoiceScannerScreen({super.key, required this.firebaseUid});

  @override
  State<InvoiceScannerScreen> createState() => _InvoiceScannerScreenState();
}

class _InvoiceScannerScreenState extends State<InvoiceScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _processing = false;
  bool _torchOn    = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || _processing) return;
    setState(() => _processing = true);
    await _ctrl.stop();

    try {
      final result = await InvoiceScannerService.processQrScan(raw, widget.firebaseUid);

      if (!mounted) return;

      if (result['duplicate'] == true) {
        final invoice = result['invoice'] as Map<String, dynamic>;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Factura duplicada',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
            content: Text(
              'Esta factura ya fue escaneada.\nComercio: ${invoice['merchant_name'] ?? '-'}\nTotal: B/. ${invoice['total_amount'] ?? '-'}',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cerrar', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoicePreviewScreen(
                        invoice: invoice,
                        firebaseUid: widget.firebaseUid,
                      ),
                    ),
                  );
                },
                child: const Text('Ver factura', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewScreen(
            invoice: result['invoice'] as Map<String, dynamic>,
            firebaseUid: widget.firebaseUid,
          ),
        ),
      );
    } catch (e) {
      // Modo offline: guardar en cola Hive
      await InvoiceOfflineQueue.queueScan(raw, widget.firebaseUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sin conexión. Factura guardada para sincronizar luego.'),
        backgroundColor: AppTheme.warning,
      ));
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Escanear Factura QR',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                color: _torchOn ? AppTheme.primary : AppTheme.textSecondary),
            onPressed: () {
              _ctrl.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            icon: Icon(Icons.flip_camera_ios, color: AppTheme.textSecondary),
            onPressed: () => _ctrl.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          // Overlay con visor
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 2.5),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0, right: 0,
            child: Center(
              child: Text(
                'Apunta el QR de tu factura DGI',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text('Consultando DGI...',
                        style: TextStyle(color: AppTheme.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
