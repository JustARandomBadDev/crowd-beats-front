import '../../models/json_fields.dart';

enum ApiFailureCategory { backend, protocol, invalidJson, transport, timeout }

class BackendError {
  const BackendError({required this.code, required this.message});

  final String code;
  final String message;

  factory BackendError.fromJson(Object? value) {
    final json = JsonFields.object(value, 'error');
    return BackendError(
      code: JsonFields.string(json, 'code'),
      message: JsonFields.string(json, 'message'),
    );
  }
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.category, {
    this.statusCode,
    this.backendError,
    this.meta,
    this.cause,
  });

  final ApiFailureCategory category;
  final int? statusCode;
  final BackendError? backendError;
  final Map<String, dynamic>? meta;
  final Object? cause;

  String? get backendCode => backendError?.code;
  String? get backendMessage => backendError?.message;

  @override
  String toString() =>
      'ApiFailure(${category.name}, status: $statusCode, '
      'code: $backendCode)';
}
