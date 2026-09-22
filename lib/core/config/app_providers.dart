import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/crowd_beats_api.dart';
import '../storage/session_storage.dart';
import '../websocket/websocket_service.dart';
import 'app_config.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  ref.onDispose(client.close);
  return client;
});

final crowdBeatsApiProvider = Provider<CrowdBeatsApi>((ref) {
  return CrowdBeatsApi(ref.watch(apiClientProvider));
});

final webSocketServiceProvider = Provider<WebSocketTransport>((ref) {
  return WebSocketService(baseUrl: AppConfig.wsBaseUrl);
});

final roomReconnectDelayProvider = Provider<Duration Function(int)>((ref) {
  return (attempt) => Duration(seconds: 1 << (attempt - 1).clamp(0, 3).toInt());
});
