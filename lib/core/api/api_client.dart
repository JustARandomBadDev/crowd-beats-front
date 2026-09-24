import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/json_fields.dart';
import 'api_failure.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = _parseBaseUrl(baseUrl),
       _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _httpClient;
  final Duration timeout;

  Future<ApiResponse<T>> get<T>(
    String path, {
    String? bearerToken,
    Map<String, String>? queryParameters,
    Set<int> additionalDataStatuses = const {},
    required T Function(Object? data) decode,
  }) => _send(
    'GET',
    path,
    bearerToken: bearerToken,
    queryParameters: queryParameters,
    additionalDataStatuses: additionalDataStatuses,
    decode: decode,
  );

  Future<ApiResponse<T>> post<T>(
    String path, {
    String? bearerToken,
    Object? body,
    required T Function(Object? data) decode,
  }) =>
      _send('POST', path, bearerToken: bearerToken, body: body, decode: decode);

  Future<ApiResponse<T>> _send<T>(
    String method,
    String path, {
    String? bearerToken,
    Map<String, String>? queryParameters,
    Object? body,
    Set<int> additionalDataStatuses = const {},
    required T Function(Object? data) decode,
  }) async {
    if (bearerToken != null && bearerToken.isEmpty) {
      throw ArgumentError.value(
        bearerToken,
        'bearerToken',
        'Must not be empty',
      );
    }

    final request = http.Request(method, _resolve(path, queryParameters));
    request.headers['Content-Type'] = 'application/json';
    if (bearerToken != null) {
      request.headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }

    late final http.Response response;
    try {
      response = await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException catch (error) {
      throw ApiFailure(ApiFailureCategory.timeout, cause: error);
    } on IOException catch (error) {
      throw ApiFailure(ApiFailureCategory.transport, cause: error);
    } on http.ClientException catch (error) {
      throw ApiFailure(ApiFailureCategory.transport, cause: error);
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw ApiFailure(
        ApiFailureCategory.invalidJson,
        statusCode: response.statusCode,
        cause: error,
      );
    }

    final Map<String, dynamic> envelope;
    final Map<String, dynamic> meta;
    try {
      envelope = JsonFields.object(decoded, 'response');
      if (!envelope.containsKey('data') ||
          !envelope.containsKey('error') ||
          !envelope.containsKey('meta')) {
        throw const FormatException('Missing data, error or meta');
      }
      meta = JsonFields.object(envelope['meta'], 'meta');
      if (envelope['data'] != null && envelope['error'] != null) {
        throw const FormatException('Response contains both data and error');
      }
    } on FormatException catch (error) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        cause: error,
      );
    }

    if (envelope['error'] != null) {
      try {
        final backendError = BackendError.fromJson(envelope['error']);
        throw ApiFailure(
          ApiFailureCategory.backend,
          statusCode: response.statusCode,
          backendError: backendError,
          meta: meta,
        );
      } on FormatException catch (error) {
        throw ApiFailure(
          ApiFailureCategory.protocol,
          statusCode: response.statusCode,
          cause: error,
        );
      }
    }

    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        !additionalDataStatuses.contains(response.statusCode)) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        meta: meta,
        cause: const FormatException('Non-success HTTP status without error'),
      );
    }

    if (envelope['data'] == null) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        meta: meta,
        cause: const FormatException('Success response has no data'),
      );
    }

    try {
      return ApiResponse(
        data: decode(envelope['data']),
        statusCode: response.statusCode,
        meta: meta,
      );
    } on FormatException catch (error) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        meta: meta,
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        meta: meta,
        cause: error,
      );
    }
  }

  Uri _resolve(String path, Map<String, String>? queryParameters) {
    final relative = Uri.parse(path);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasQuery ||
        relative.hasFragment) {
      throw ArgumentError.value(path, 'path', 'Expected an endpoint path');
    }
    return _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        ...relative.pathSegments.where((segment) => segment.isNotEmpty),
      ],
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }

  void close() => _httpClient.close();

  static Uri _parseBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        value,
        'baseUrl',
        'Expected an HTTP(S) base URL',
      );
    }
    return uri;
  }
}

class ApiResponse<T> {
  const ApiResponse({
    required this.data,
    required this.statusCode,
    required this.meta,
  });

  final T data;
  final int statusCode;
  final Map<String, dynamic> meta;
}
