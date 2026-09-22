class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:8080/ws',
  );

  static void validate() {
    _validateUrl(apiBaseUrl, 'API_BASE_URL', {'http', 'https'});
    _validateUrl(wsBaseUrl, 'WS_BASE_URL', {'ws', 'wss'});
  }

  static void _validateUrl(String value, String name, Set<String> schemes) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !schemes.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('Invalid $name: expected a ${schemes.join('/')} URL');
    }
  }
}
