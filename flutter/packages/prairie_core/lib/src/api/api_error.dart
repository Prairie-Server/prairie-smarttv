/// Mirrors `ApiError` from src/api/client.ts.
class ApiError implements Exception {
  ApiError(this.message, this.status, [this.code, this.body]);

  final String message;
  final int status;
  final String? code;
  final Object? body;

  @override
  String toString() => 'ApiError($status${code != null ? ', $code' : ''}): $message';
}
