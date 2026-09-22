import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_controller.dart';

class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionControllerProvider);
    final active = state.active!;
    final controller = ref.read(sessionControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Crowd Beats')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You are in ${active.roomName ?? 'room ${active.roomId}'}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('Nickname: ${active.nickname}'),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: state.busy ? null : controller.startRoomSwitch,
                  child: const Text('Scan another room'),
                ),
                FilledButton(
                  onPressed: state.busy ? null : controller.leave,
                  child: state.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Leave room'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
