import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Minimal [HttpClientAdapter] fake for testing [ApiClient] without a real
/// network — mirrors the role `fetchImpl` mocks play in client.test.ts.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  /// Given the requested path (query string included), returns the fake
  /// response. Throw to simulate a network failure.
  final ResponseBody Function(RequestOptions options) handler;

  int callCount = 0;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(String body, int statusCode, {String? statusMessage}) =>
    ResponseBody.fromString(body, statusCode, statusMessage: statusMessage, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
