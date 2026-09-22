import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session.phase == SessionPhase.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Crowd Beats')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.message ?? 'Could not restore the session.'),
                const SizedBox(height: 16),
                if (session.pendingJoin != null)
                  FilledButton(
                    onPressed: session.busy
                        ? null
                        : () => ref
                              .read(sessionControllerProvider.notifier)
                              .retrySave(),
                    child: const Text('Retry saving session'),
                  )
                else
                  FilledButton(
                    onPressed: session.busy
                        ? null
                        : () => ref
                              .read(sessionControllerProvider.notifier)
                              .bootstrap(),
                    child: const Text('Retry'),
                  ),
              ],
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
