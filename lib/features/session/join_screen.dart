import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_scanner_screen.dart';
import 'session_controller.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _nicknameController = TextEditingController();
  String? _qrCode;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (!mounted || code == null) return;
    setState(() => _qrCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(state.switching ? 'Change room' : 'Join a room'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Scan the venue QR code to join.'),
                if (state.phase == SessionPhase.invalid) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Your previous session expired. Scan a QR code to join again.',
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: state.busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(
                    _qrCode == null ? 'Scan QR code' : 'Scan another QR code',
                  ),
                ),
                if (_qrCode != null) const Text('QR code scanned.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _nicknameController,
                  enabled: !state.busy,
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    helperText: '1–32 characters',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (state.message != null) ...[
                  Text(
                    state.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.join(
                          qrCode: _qrCode ?? '',
                          nickname: _nicknameController.text,
                        ),
                  child: state.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join room'),
                ),
                if (state.switching) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: state.busy ? null : controller.cancelRoomSwitch,
                    child: const Text('Back to current room'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
