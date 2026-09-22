import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _accepted = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_accepted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _accepted = true;
      try {
        await _scanner.stop();
      } on Object {
        // The camera can finish closing while this screen is being dismissed.
      }
      if (mounted) Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan venue QR')),
      body: MobileScanner(
        controller: _scanner,
        onDetect: _onDetect,
        errorBuilder: (context, error) => const Center(
          child: Text('Camera unavailable. Check camera access and try again.'),
        ),
      ),
    );
  }
}
