import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../storage/session_storage.dart';
import '../websocket/websocket_service.dart';
import 'app_config.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final sessionStorage = ref.watch(sessionStorageProvider);

  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: sessionStorage.readToken,
  );
});

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService(baseUrl: AppConfig.wsBaseUrl);
  ref.onDispose(service.dispose);
  return service;
});
