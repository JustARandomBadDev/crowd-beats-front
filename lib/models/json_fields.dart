class JsonFields {
  static Map<String, dynamic> object(Object? value, String name) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Expected object at $name');
  }

  static Map<String, dynamic> nested(Map<String, dynamic> json, String key) {
    return object(_required(json, key), key);
  }

  static String string(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value is String) return value;
    throw FormatException('Expected string at $key');
  }

  static String? nullableString(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value == null || value is String) return value as String?;
    throw FormatException('Expected string or null at $key');
  }

  static int integer(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value is int) return value;
    throw FormatException('Expected int at $key');
  }

  static int? nullableInt(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value == null || value is int) return value as int?;
    throw FormatException('Expected int or null at $key');
  }

  static bool boolean(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value is bool) return value;
    throw FormatException('Expected bool at $key');
  }

  static List<dynamic> list(Map<String, dynamic> json, String key) {
    final value = _required(json, key);
    if (value is List<dynamic>) return value;
    throw FormatException('Expected list at $key');
  }

  static DateTime dateTime(Map<String, dynamic> json, String key) {
    final value = string(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    throw FormatException('Expected RFC3339 timestamp at $key');
  }

  static DateTime? nullableDateTime(Map<String, dynamic> json, String key) {
    final value = nullableString(json, key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    throw FormatException('Expected RFC3339 timestamp or null at $key');
  }

  static Object? _required(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) throw FormatException('Missing field $key');
    return json[key];
  }
}
