import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xLarge,
              AppSpacing.xxLarge,
              AppSpacing.xLarge,
              AppSpacing.xLarge,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  minHeight:
                      constraints.maxHeight -
                      AppSpacing.xxLarge -
                      AppSpacing.xLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: AppSpacing.xLarge),
                    Text(
                      state.switching ? 'Change the room' : 'Join a room',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      state.switching
                          ? 'Scan the new venue code. Your current room stays active until the switch succeeds.'
                          : 'Scan the venue code and choose a nickname. No account needed.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (state.phase == SessionPhase.invalid) ...[
                      const SizedBox(height: AppSpacing.large),
                      const AppMessageCard(
                        message:
                            'Your previous session expired. Scan a QR code to join again.',
                        tone: AppMessageTone.warning,
                        compact: true,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xLarge),
                    OutlinedButton.icon(
                      onPressed: state.busy ? null : _scan,
                      icon: Icon(
                        _qrCode == null
                            ? Icons.qr_code_scanner_rounded
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        _qrCode == null
                            ? 'Scan QR code'
                            : 'Scan another QR code',
                      ),
                    ),
                    if (_qrCode != null) ...[
                      const SizedBox(height: AppSpacing.small),
                      const Align(
                        alignment: Alignment.center,
                        child: AppStatusChip(
                          label: 'QR code scanned',
                          icon: Icons.check_rounded,
                          tone: AppMessageTone.success,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.large),
                    TextField(
                      controller: _nicknameController,
                      enabled: !state.busy,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Nickname',
                        helperText: '1–32 characters',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onSubmitted: state.busy
                          ? null
                          : (_) => controller.join(
                              qrCode: _qrCode ?? '',
                              nickname: _nicknameController.text,
                            ),
                    ),
                    if (state.message != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      AppMessageCard(
                        message: state.message!,
                        tone: AppMessageTone.error,
                        compact: true,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.large),
                    FilledButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => controller.join(
                              qrCode: _qrCode ?? '',
                              nickname: _nicknameController.text,
                            ),
                      icon: state.busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(state.busy ? 'Joining…' : 'Join room'),
                    ),
                    if (state.switching) ...[
                      const SizedBox(height: AppSpacing.small),
                      TextButton.icon(
                        onPressed: state.busy
                            ? null
                            : controller.cancelRoomSwitch,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back to current room'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surfaceStrong,
            borderRadius: BorderRadius.circular(AppRadii.large),
            border: Border.all(color: AppColors.purpleMuted),
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: AppColors.purpleLight,
            size: 34,
          ),
        ),
        const SizedBox(height: AppSpacing.medium),
        Text(
          'CROWDBEATS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.purpleLight,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
