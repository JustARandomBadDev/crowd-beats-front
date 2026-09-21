import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _baseUri = Uri.parse(baseUrl),
       _httpClient = httpClient ?? http.Client(),
       _tokenProvider = tokenProvider;

  final Uri _baseUri;
  final http.Client _httpClient;
  final Future<String?> Function()? _tokenProvider;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(Object? json)? decoder,
  }) {
    return _send<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      decoder: decoder,
    );
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    T Function(Object? json)? decoder,
  }) {
    return _send<T>(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      decoder: decoder,
    );
  }

  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(Object? json)? decoder,
  }) {
    return _send<T>(
      'DELETE',
      path,
      queryParameters: queryParameters,
      decoder: decoder,
    );
  }

  Future<ApiResponse<T>> _send<T>(
    String method,
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    T Function(Object? json)? decoder,
  }) async {
    final request = http.Request(method, _resolve(path, queryParameters));
    request.headers.addAll(await _headers());

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    final decodedBody = _decodeBody(response.body);
    final apiResponse = ApiResponse<T>.fromJson(decodedBody, decoder: decoder);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessage(apiResponse.error) ?? response.reasonPhrase,
        response: apiResponse,
      );
    }

    if (apiResponse.error != null) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _errorMessage(apiResponse.error),
        response: apiResponse,
      );
    }

    return apiResponse;
  }

  Uri _resolve(String path, Map<String, String>? queryParameters) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = _baseUri.resolve(normalizedPath);

    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParameters},
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider?.call();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Object? _decodeBody(String body) {
    if (body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  String? _errorMessage(Object? error) {
    if (error == null) {
      return null;
    }

    if (error is String) {
      return error;
    }

    if (error is Map<String, dynamic>) {
      final message = error['message'] ?? error['Message'] ?? error['error'];
      return message?.toString();
    }

    return error.toString();
  }
}

class ApiResponse<T> {
  const ApiResponse({
    required this.data,
    required this.error,
    required this.meta,
    required this.raw,
  });

  final T? data;
  final Object? error;
  final Map<String, dynamic>? meta;
  final Object? raw;

  factory ApiResponse.fromJson(
    Object? json, {
    T Function(Object? json)? decoder,
  }) {
    if (json is Map<String, dynamic> &&
        (json.containsKey('data') ||
            json.containsKey('error') ||
            json.containsKey('meta'))) {
      final rawData = json['data'];

      return ApiResponse<T>(
        data: decoder != null ? decoder(rawData) : rawData as T?,
        error: json['error'],
        meta: json['meta'] is Map<String, dynamic>
            ? json['meta'] as Map<String, dynamic>
            : null,
        raw: json,
      );
    }

    return ApiResponse<T>(
      data: decoder != null ? decoder(json) : json as T?,
      error: null,
      meta: null,
      raw: json,
    );
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.response,
    this.message,
  });

  final int statusCode;
  final String? message;
  final ApiResponse<Object?> response;

  @override
  String toString() {
    final details = message == null ? '' : ': $message';
    return 'ApiException($statusCode)$details';
  }
}
