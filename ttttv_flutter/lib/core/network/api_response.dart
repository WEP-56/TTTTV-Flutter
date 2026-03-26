class ApiResponse<T> {
  ApiResponse({
    required this.success,
    required this.data,
    this.message,
    this.error,
  });

  final bool success;
  final T? data;
  final String? message;
  final String? error;

  factory ApiResponse.fromJson(
    Object? json,
    T Function(Object? json) decoder,
  ) {
    final map = json as Map<String, dynamic>;
    return ApiResponse<T>(
      success: map['success'] as bool? ?? false,
      data: map['data'] == null ? null : decoder(map['data']),
      message: map['message'] as String?,
      error: map['error'] as String?,
    );
  }
}
