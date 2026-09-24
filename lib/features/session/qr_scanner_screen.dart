import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

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
      appBar: AppBar(
        title: const Text('Scan venue code'),
        leading: IconButton(
          tooltip: 'Close scanner',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            useAppLifecycleState: false,
            onDetect: _onDetect,
            placeholderBuilder: (context) =>
                const AppLoadingState(label: 'Starting camera…'),
            errorBuilder: (context, error) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                child: AppMessageCard(
                  title: 'Camera unavailable',
                  message:
                      'Allow camera access in your device settings, then try again.',
                  tone: AppMessageTone.error,
                  icon: Icons.no_photography_outlined,
                  action: FilledButton.icon(
                    onPressed: () => unawaited(_scanner.start()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _scanner,
            builder: (context, scannerState, _) {
              if (_accepted || !scannerState.isRunning) {
                return const SizedBox.shrink();
              }
              return const IgnorePointer(child: _ScannerOverlay());
            },
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        children: [
          const _ScannerInstruction(),
          const Spacer(),
          const _ScannerFrame(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.large,
              vertical: AppSpacing.medium,
            ),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.center_focus_strong_rounded,
                  size: 18,
                  color: AppColors.purpleLight,
                ),
                SizedBox(width: AppSpacing.small),
                Flexible(
                  child: Text(
                    'Hold steady until the code is recognized',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerInstruction extends StatelessWidget {
  const _ScannerInstruction();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.medium,
      ),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'Place the venue QR code inside the frame',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width.clamp(220.0, 280.0);
    return Semantics(
      label: 'QR scanning area',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.large),
          border: Border.all(color: AppColors.purpleLight, width: 3),
        ),
      ),
    );
  }
}
