import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_response.dart';

class HttpBackendClient {
  HttpBackendClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
        );

  final Dio _dio;

  Future<T> getData<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return _unwrap(response.data, decoder);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<T> getRaw<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return decoder(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<T> postData<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: body,
        queryParameters: queryParameters,
      );
      return _unwrap(response.data, decoder);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<T> deleteData<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
  }) async {
    try {
      final response = await _dio.delete<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return _unwrap(response.data, decoder);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> postVoid(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
  }) async {
    await postData<void>(
      path,
      body: body,
      queryParameters: queryParameters,
      decoder: (_) {},
    );
  }

  Future<void> deleteVoid(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    await deleteData<void>(
      path,
      queryParameters: queryParameters,
      decoder: (_) {},
    );
  }

  T _unwrap<T>(Object? raw, T Function(Object? json) decoder) {
    final envelope = ApiResponse<T>.fromJson(raw, decoder);
    if (!envelope.success) {
      throw ApiException(envelope.error ?? envelope.message ?? 'Request failed');
    }
    if (envelope.data == null) {
      return decoder(null);
    }
    return envelope.data as T;
  }
}
