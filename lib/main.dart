import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_widgets.dart';
import 'features/room/room_screen.dart';
import 'features/session/join_screen.dart';
import 'features/session/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  runApp(const ProviderScope(child: CrowdBeatsApp()));
}

class CrowdBeatsApp extends StatelessWidget {
  const CrowdBeatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crowd Beats',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SessionGateway(),
    );
  }
}

class SessionGateway extends ConsumerStatefulWidget {
  const SessionGateway({super.key});

  @override
  ConsumerState<SessionGateway> createState() => _SessionGatewayState();
}

class _SessionGatewayState extends ConsumerState<SessionGateway> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(sessionControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (session.phase == SessionPhase.checking) {
      return const Scaffold(
        body: AppLoadingState(label: 'Getting your room ready…'),
      );
    }
    if (session.phase == SessionPhase.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('CrowdBeats')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AppMessageCard(
                title: 'Could not restore your room',
                message: session.message ?? 'Please check your connection.',
                tone: AppMessageTone.error,
                action: FilledButton.icon(
                  onPressed: session.busy
                      ? null
                      : session.pendingJoin != null
                      ? () => ref
                            .read(sessionControllerProvider.notifier)
                            .retrySave()
                      : () => ref
                            .read(sessionControllerProvider.notifier)
                            .bootstrap(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    session.pendingJoin != null
                        ? 'Retry saving session'
                        : 'Retry',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (session.phase == SessionPhase.active && !session.switching) {
      return const RoomScreen();
    }
    return const JoinScreen();
  }
}
