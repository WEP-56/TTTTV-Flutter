import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final backendError = data['error'] ?? data['message'];
      if (backendError is String && backendError.isNotEmpty) {
        return ApiException(backendError, statusCode: statusCode);
      }
    }

    return ApiException(
      error.message ?? 'Backend request failed',
      statusCode: statusCode,
    );
  }

  @override
  String toString() => message;
}
