import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  final _scanner = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
  );
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_scanner.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scanner.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_accepted) unawaited(_scanner.start());
      case AppLifecycleState.inactive:
        unawaited(_scanner.stop());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
    }
  }

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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    unawaited(_scanner.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan venue QR')),
      body: MobileScanner(
        controller: _scanner,
        useAppLifecycleState: false,
        onDetect: _onDetect,
        errorBuilder: (context, error) => const Center(
          child: Text('Camera unavailable. Check camera access and try again.'),
        ),
      ),
    );
  }
}
