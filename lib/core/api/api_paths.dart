class ApiPaths {
  static const readiness = '/health/ready';
  static const joinByQr = '/api/v1/rooms/join-by-qr';
  static const currentSession = '/api/v1/sessions/me';
  static const heartbeat = '/api/v1/sessions/heartbeat';
  static const leave = '/api/v1/sessions/leave';
  static const spotifySearch = '/api/v1/spotify/search';

  static String room(String roomId) =>
      '/api/v1/rooms/${Uri.encodeComponent(roomId)}';

  static String queue(String roomId) => '${room(roomId)}/queue';
  static String tracks(String roomId) => '${room(roomId)}/tracks';
  static String votes(String roomId) => '${room(roomId)}/votes';
}
