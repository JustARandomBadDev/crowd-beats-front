import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_failure.dart';
import 'core/config/app_config.dart';
import 'core/config/app_providers.dart';

void main() {
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
      home: const AppReadyScreen(),
    );
  }
}

class AppReadyScreen extends ConsumerStatefulWidget {
  const AppReadyScreen({super.key});

  @override
  ConsumerState<AppReadyScreen> createState() => _AppReadyScreenState();
}

class _AppReadyScreenState extends ConsumerState<AppReadyScreen> {
  String? _apiStatus;

  Future<void> _testApi() async {
    setState(() => _apiStatus = 'Testing API...');

    try {
      final response = await ref.read(crowdBeatsApiProvider).readiness();
      if (!mounted) return;
      setState(() => _apiStatus = 'API reachable: ${response.data.status}');
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _apiStatus =
            'API ${error.category.name}: ${error.statusCode ?? 'no status'} '
            '${error.backendCode ?? ''}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _apiStatus = 'API unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crowd Beats')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'App ready',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'API: ${AppConfig.apiBaseUrl}\nWS: ${AppConfig.wsBaseUrl}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _testApi,
                  child: const Text('Test API'),
                ),
                if (_apiStatus != null) ...[
                  const SizedBox(height: 16),
                  Text(_apiStatus!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
